--[[
    server/storage.lua

    The database half of persistence. Optional in the strongest sense: when oxmysql is not
    started, every function here returns "no stored settings" and the resource carries on with
    the client's own KVP copy. Nothing above this file has to know which of the two happened.

    The table is created on first start. It is the only table this resource owns, and it is
    never anything but its own - a HUD has no business writing into a framework's rows.
]]

Storage = {}

local ready = false
local usable = false

local function mysqlStarted()
    local state = GetResourceState('oxmysql')
    return state == 'started' or state == 'starting'
end

--- Create the table if it is missing. Runs once, on the first call, and marks the store
--- unusable rather than raising if anything goes wrong: a HUD that refuses to load because
--- of a database is a worse outcome than a HUD whose settings do not follow the player.
local function ensure()
    if ready then return usable end
    ready = true

    if not Config.Persistence.database then
        HUD.debug('storage: disabled in config')
        return false
    end

    if not mysqlStarted() then
        HUD.warn('oxmysql is not started - HUD settings will be stored on each player\'s machine only.')
        return false
    end

    local name = Config.Persistence.table
    -- The table name comes from config.lua, which is operator-authored and not player input,
    -- but it is still concatenated into DDL. Anything but word characters is refused rather
    -- than escaped, because there is no legitimate table name this rejects.
    if type(name) ~= 'string' or not name:match('^%w[%w_]*$') then
        HUD.warn(('Config.Persistence.table is not a valid table name (%s) - database storage is off.'):format(tostring(name)))
        return false
    end

    local ok = pcall(function()
        exports.oxmysql:query_async(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                `identifier` VARCHAR(64) NOT NULL,
                `settings` LONGTEXT NOT NULL,
                `updated_at` BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(name), {})
    end)

    if not ok then
        HUD.warn('Could not create the HUD settings table - database storage is off.')
        return false
    end

    usable = true
    HUD.debug('storage: ready')
    return true
end

--- Whether the database side is available. Used by the load path to decide whether it is
--- worth waiting on a query at all.
function Storage.available()
    return ensure()
end

--- Stored settings for `identifier`, plus the timestamp they were written at. Returns nil
--- when there is no row, when the store is off, or when the stored JSON no longer parses -
--- all three mean the same thing to the caller: use the other copy.
function Storage.load(identifier)
    if not identifier or not ensure() then return nil, 0 end

    local ok, row = pcall(function()
        return exports.oxmysql:single_async(
            ('SELECT `settings`, `updated_at` FROM `%s` WHERE `identifier` = ?'):format(Config.Persistence.table),
            { identifier }
        )
    end)

    if not ok or type(row) ~= 'table' or not row.settings then return nil, 0 end

    local decoded, parsed = pcall(json.decode, row.settings)
    if not decoded or type(parsed) ~= 'table' then return nil, 0 end

    return parsed, tonumber(row.updated_at) or 0
end

--- Write `settings` for `identifier`. Fire and forget: the client already has the value
--- applied, so a failed write costs the player nothing until they change machines.
function Storage.save(identifier, settings, timestamp)
    if not identifier or not ensure() then return false end

    local encoded = json.encode(settings)
    if type(encoded) ~= 'string' then return false end

    local ok = pcall(function()
        exports.oxmysql:prepare(
            ('INSERT INTO `%s` (`identifier`, `settings`, `updated_at`) VALUES (?, ?, ?) ' ..
             'ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`), `updated_at` = VALUES(`updated_at`)')
                :format(Config.Persistence.table),
            { identifier, encoded, timestamp or os.time() }
        )
    end)

    return ok
end

--- Delete the stored row. Called when a player resets their HUD, so that a reset on one
--- machine is not undone by the stored copy the next time they log in elsewhere.
function Storage.clear(identifier)
    if not identifier or not ensure() then return false end

    return pcall(function()
        exports.oxmysql:prepare(
            ('DELETE FROM `%s` WHERE `identifier` = ?'):format(Config.Persistence.table),
            { identifier }
        )
    end)
end
