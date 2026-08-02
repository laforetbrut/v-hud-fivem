--[[
    server/odometer.lua

    The stored half of the odometer: one row per number plate, in metres.

    The client measures and the server accumulates, because a client that could SET its own
    mileage could set it to anything. What a client is allowed to say is "I drove this far
    since the last time I told you", and even that is capped: a plausible increment is a few
    hundred metres, so anything larger is discarded rather than added.

    Optional like every other stored thing here. With no database the counter still works for
    the session; it just does not survive a restart.
]]

local ready = false
local usable = false

-- Plate -> metres, so a read does not hit the database on every entry into a car.
local cache = {}

local function ensure()
    if ready then return usable end
    ready = true

    if not Config.Odometer.enabled or not Config.Odometer.track then return false end
    if not Storage.available() then
        HUD.debug('odometer: no database, mileage will not survive a restart')
        return false
    end

    local name = Config.Odometer.table
    if type(name) ~= 'string' or not name:match('^%w[%w_]*$') then
        HUD.warn(('Config.Odometer.table is not a valid table name (%s) - mileage is off.')
            :format(tostring(name)))
        return false
    end

    local ok = pcall(function()
        exports.oxmysql:query_async(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                `plate` VARCHAR(12) NOT NULL,
                `metres` BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(name), {})
    end)

    if not ok then
        HUD.warn('Could not create the odometer table - mileage will not be stored.')
        return false
    end

    usable = true
    return true
end

--- Metres for `plate`, from the cache or the database. 0 for a plate never seen.
local function read(plate)
    if cache[plate] then return cache[plate] end
    if not ensure() then
        cache[plate] = 0
        return 0
    end

    local ok, row = pcall(function()
        return exports.oxmysql:single_async(
            ('SELECT `metres` FROM `%s` WHERE `plate` = ?'):format(Config.Odometer.table),
            { plate }
        )
    end)

    cache[plate] = (ok and type(row) == 'table' and tonumber(row.metres)) or 0
    return cache[plate]
end

--- Sanity-check a plate before it becomes a database key. Eight characters is the game's
--- limit; anything longer or with control characters in it did not come from a vehicle.
local function validPlate(plate)
    return type(plate) == 'string'
        and #plate > 0
        and #plate <= 12
        and plate:match('^[%w%s%-]+$') ~= nil
end

RegisterNetEvent('vhud:server:OdometerRequest', function(plate)
    if not Config.Odometer.enabled or not validPlate(plate) then return end
    TriggerClientEvent('vhud:client:Odometer', source, plate, read(plate))
end)

RegisterNetEvent('vhud:server:Odometer', function(plate, metres)
    if not Config.Odometer.enabled or not Config.Odometer.track then return end
    if not validPlate(plate) then return end

    local added = tonumber(metres)
    if not added or added ~= added or added <= 0 then return end

    -- The client reports at most Config.Odometer.saveEvery metres per message, plus whatever
    -- one sampling interval can add. Twice that is generous and still refuses a client
    -- claiming it drove to the moon.
    local ceiling = (Config.Odometer.saveEvery or 1000) * 2 + 500
    if added > ceiling then
        -- %s, not %d: `added` came from a client and Lua's %d raises on a fraction, on inf and
        -- on anything past an integer's range. A malformed value must be refused, not turned
        -- into a server-side error by the line that refuses it. `ceiling` is the operator's and
        -- always integral, so its %d is safe.
        HUD.debug(('odometer: refused %s m for %s (ceiling %d)'):format(tostring(added), plate, ceiling))
        return
    end

    local total = read(plate) + math.floor(added)
    cache[plate] = total

    if not ensure() then return end

    pcall(function()
        exports.oxmysql:prepare(
            ('INSERT INTO `%s` (`plate`, `metres`) VALUES (?, ?) ' ..
             'ON DUPLICATE KEY UPDATE `metres` = VALUES(`metres`)'):format(Config.Odometer.table),
            { plate, total }
        )
    end)
end)

-- ---------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------

--- Metres on a plate. For a mechanic script that prices a service by mileage, or a dealership
--- that wants to show one.
exports('GetOdometer', function(plate)
    if not validPlate(plate) then return 0 end
    return read(plate)
end)

--- Set a plate's mileage outright: a rebuilt engine, an imported vehicle, an admin fixing a
--- number that a crash left wrong.
exports('SetOdometer', function(plate, metres)
    if not validPlate(plate) then return false end

    local value = math.floor(math.max(0, tonumber(metres) or 0))
    cache[plate] = value

    if not ensure() then return true end

    return pcall(function()
        exports.oxmysql:prepare(
            ('INSERT INTO `%s` (`plate`, `metres`) VALUES (?, ?) ' ..
             'ON DUPLICATE KEY UPDATE `metres` = VALUES(`metres`)'):format(Config.Odometer.table),
            { plate, value }
        )
    end)
end)
