--[[
    bridge/server/framework.lua

    The server's half of the compatibility layer. Everything the server needs to know about a
    player - who they are, what job they hold, what their stress is - is asked for here, so no
    file above this one names a framework.

    ---------------------------------------------------------------------------------------
    HOW A FRAMEWORK IS ADDED
    ---------------------------------------------------------------------------------------

    Each one is an ADAPTER: a table of small functions with the same names, listed in
    ADAPTERS below. `Bridge.core()` picks the first whose resource is started and whose
    handshake answers, and every `Bridge.*` function below then calls through the chosen
    adapter. Nothing branches on a framework name outside this file.

    Four are shipped:

        qb-core / qbx_core    the same PlayerData shape and the same GetCoreObject export,
                              so one adapter serves both
        es_extended (ESX)     a different object, a different notification path, and no
                              metadata table - see the note on the ESX adapter
        ox_core               a different object again, with groups instead of jobs

    Anything else degrades to standalone: settings still save to KVP on the client, stress is
    simply not persisted, and nothing errors. That is a supported configuration, not a
    failure mode.

    Set Config.Compat.forceFramework to skip detection on a server that has two installed.
]]

Bridge = {}

local core
local adapter
local frameworkName

local function started(resource)
    if not resource or resource == '' then return false end
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

--[[
    Read a field from the framework object without raising.

    ox_core's "core object" IS its exports table, and in FiveM indexing an export that does
    not exist RAISES rather than returning nil. So any `core.Functions` written for qb-core's
    shape is a crash on an ox_core server.

    Exposed on Bridge because server/main.lua's qb-hud compatibility shim needs it too.
    Anything framework-SPECIFIC belongs in that framework's adapter instead of here.
]]
function Bridge.field(object, name)
    if type(object) ~= 'table' then return nil end
    local ok, value = pcall(function() return object[name] end)
    if not ok then return nil end
    return value
end

--- Call `fn` and return its result, or nil if it threw. Every call into somebody else's code
--- goes through here: a framework that changed a signature between versions must degrade,
--- never take the HUD down with it.
local function try(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

-- ---------------------------------------------------------------------------------------
-- The adapters
-- ---------------------------------------------------------------------------------------

local ADAPTERS = {}

--[[
    qb-core and qbx_core.

    qbx_core publishes the same GetCoreObject export and the same PlayerData shape, so it
    needs no separate adapter. This is the path that is actually exercised in production; the
    others are written from each framework's published API.
]]
ADAPTERS.qb = {
    resources = { 'qb-core', 'qbx_core' },

    handshake = function(resource)
        local object = try(function() return exports[resource]:GetCoreObject() end)
        return type(object) == 'table' and object or nil
    end,

    player = function(object, src)
        -- qb-core moved GetPlayer to a resource export and kept the Functions one as an
        -- alias. Try the export first so a build that dropped the alias still works.
        local player = try(function() return exports[frameworkName]:GetPlayer(src) end)
        if type(player) == 'table' then return player end

        if object.Functions and object.Functions.GetPlayer then
            player = try(object.Functions.GetPlayer, src)
            if type(player) == 'table' then return player end
        end

        return nil
    end,

    citizenId = function(_, player)
        return player and player.PlayerData and player.PlayerData.citizenid or nil
    end,

    license = function(_, player)
        return player and player.PlayerData and player.PlayerData.license or nil
    end,

    roles = function(_, player)
        local data = player and player.PlayerData
        if not data then return nil end
        return {
            job = (data.job and data.job.name) or '',
            jobType = (data.job and data.job.type) or '',
            gang = (data.gang and data.gang.name) or '',
        }
    end,

    metadata = function(_, player, field)
        local data = player and player.PlayerData
        if not data or not data.metadata then return nil end
        return data.metadata[field]
    end,

    setMetadata = function(_, player, field, value)
        if not player or not player.SetMetaData then return false end
        -- SetMetaData is bound by qb-core's buildMethodTable, so the dot call is correct:
        -- the player is already captured in the closure.
        return pcall(player.SetMetaData, field, value)
    end,

    notify = function(object, src, message, kind)
        if object.Functions and object.Functions.Notify then
            return pcall(object.Functions.Notify, src, message, kind or 'primary')
        end
        return false
    end,

    isAdmin = function(object, src)
        if object.Functions and object.Functions.HasPermission then
            local allowed = try(object.Functions.HasPermission, src, 'admin')
            return allowed == true
        end
        return false
    end,

    addCommand = function(object, name, help, args, restricted, handler)
        if not (object.Commands and object.Commands.Add) then return false end
        -- The sixth argument is a PERMISSION STRING ('admin'), not a boolean. Passing `true`
        -- there makes qb-core print a warning trace on every boot, because it tries to build
        -- an ace name out of it.
        local permission = restricted and 'admin' or nil
        return pcall(object.Commands.Add, name, help, args or {}, false, handler, permission)
    end,
}

--[[
    ESX (es_extended).

    Two differences worth knowing before changing anything here:

      * THERE IS NO METADATA TABLE. qb-core keeps hunger, thirst and stress in
        PlayerData.metadata; ESX keeps hunger and thirst in esx_status, which lives on the
        CLIENT and is pushed to the server by that resource, and has no notion of stress at
        all. So `metadata` reads from a per-player table this file maintains from the events
        esx_status fires, and `setMetadata` writes back through esx_status where a field maps
        onto it and holds the value locally where it does not.

      * THERE IS NO GANG. `gang` is returned as an empty string, so Config.JobOverrides keys
        of the form 'gang:name' simply never match on an ESX server. Job grade is exposed as
        jobType, which is the closest equivalent and what an operator will expect to key on.
]]
local esxStatus = {}          -- src -> { hunger = n, thirst = n, stress = n }

-- esx_status publishes on a tick. Both the modern and the legacy event names are listened
-- for; an unused one costs a registration and nothing else.
for _, event in ipairs({ 'esx_status:onTick', 'esx_status:update' }) do
    RegisterNetEvent(event, function(statuses)
        -- `source` is a magic global inside a net event handler, but indexing a table with
        -- nil is a hard error rather than a miss, so it is checked before it is used.
        local src = source
        if not src or type(statuses) ~= 'table' then return end

        esxStatus[src] = esxStatus[src] or {}
        for _, status in pairs(statuses) do
            local name = type(status) == 'table' and (status.name or status.getName) or nil
            local value = type(status) == 'table' and (status.percent or status.val) or nil
            if type(name) == 'string' and tonumber(value) then
                -- esx_status stores 0-1000000; percent is already 0-100 when present.
                local number = tonumber(value)
                if number > 100 then number = number / 10000 end
                esxStatus[src][name] = HUD.clamp(number, 0, 100, nil)
            end
        end
    end)
end

AddEventHandler('playerDropped', function()
    esxStatus[source] = nil
end)

ADAPTERS.esx = {
    resources = { 'es_extended' },

    handshake = function(resource)
        -- Modern ESX publishes an export; older builds only answer the event.
        local object = try(function() return exports[resource]:getSharedObject() end)
        if type(object) == 'table' then return object end

        local fetched
        try(function() TriggerEvent('esx:getSharedObject', function(o) fetched = o end) end)
        return type(fetched) == 'table' and fetched or nil
    end,

    player = function(object, src)
        local player = try(object.GetPlayerFromId, src)
        return type(player) == 'table' and player or nil
    end,

    citizenId = function(_, player)
        -- ESX has no citizenid. The identifier is the stable per-character key, which is what
        -- 'character' scope means on this framework.
        return player and player.identifier or nil
    end,

    license = function(_, player)
        return player and player.identifier or nil
    end,

    roles = function(_, player)
        if not player then return nil end
        local job = player.job or {}
        return {
            job = job.name or '',
            -- No job "type" in ESX. The grade name is the closest thing an operator can key
            -- an override on, and it is what they will reach for.
            jobType = job.grade_name or '',
            gang = '',
        }
    end,

    metadata = function(_, player, field)
        local src = player and player.source
        local held = src and esxStatus[src]
        if held and held[field] ~= nil then return held[field] end

        -- Some ESX forks do carry a metadata bag. Read it when it is there.
        local meta = player and player.getMeta and try(player.getMeta, field)
        if meta ~= nil then return meta end

        return nil
    end,

    setMetadata = function(_, player, field, value)
        local src = player and player.source
        if not src then return false end

        if player.setMeta then
            if pcall(player.setMeta, field, value) then return true end
        end

        -- Held locally so a read straight after a write is consistent. esx_status owns the
        -- real hunger and thirst values and will overwrite these on its next tick, which is
        -- correct: it is the authority on them, not this resource.
        esxStatus[src] = esxStatus[src] or {}
        esxStatus[src][field] = value
        return true
    end,

    notify = function(_, src, message, kind)
        local types = { primary = 'info', success = 'success', error = 'error' }
        TriggerClientEvent('esx:showNotification', src, message, types[kind] or 'info')
        return true
    end,

    isAdmin = function(object, src)
        local player = try(object.GetPlayerFromId, src)
        local group = player and player.getGroup and try(player.getGroup)
        return group == 'admin' or group == 'superadmin' or group == 'owner'
    end,

    addCommand = function(object, name, help, args, restricted, handler)
        if type(object.RegisterCommand) ~= 'function' then return false end

        -- ESX's signature is (name, group, cb, allowConsole, suggestion). Its callback gets
        -- (xPlayer, args, showError) rather than (source, rawArgs), so it is adapted here
        -- instead of leaking the difference to the caller.
        return pcall(object.RegisterCommand, name, restricted and 'admin' or 'user',
            function(xPlayer, commandArgs)
                handler(xPlayer and xPlayer.source or 0, commandArgs)
            end, true, { help = help, validate = false, arguments = args or {} })
    end,
}

--[[
    ox_core.

    Groups rather than jobs, and metadata through get/set on the player object. ox_core has no
    notification system of its own, so notifications fall through to the HUD's own toast,
    which is the correct answer rather than a compromise.
]]
ADAPTERS.ox = {
    resources = { 'ox_core' },

    handshake = function(resource)
        -- ox_core exposes its API as exports rather than one object. The handshake proves the
        -- export answers; the "object" is the export table itself.
        local ok = try(function() return exports[resource]:GetPlayers() end)
        if ok == nil then return nil end
        return exports[resource]
    end,

    player = function(object, src)
        local player = try(function() return object:GetPlayer(src) end)
        return type(player) == 'table' and player or nil
    end,

    citizenId = function(_, player)
        return player and (player.stateId or player.charId) or nil
    end,

    license = function(_, player)
        return player and player.userId and tostring(player.userId) or nil
    end,

    roles = function(_, player)
        if not player then return nil end

        local groups = player.getGroups and try(player.getGroups) or nil
        local name, grade = '', ''
        if type(groups) == 'table' then
            for group, rank in pairs(groups) do
                name, grade = group, tostring(rank)
                break
            end
        end

        return { job = name, jobType = grade, gang = '' }
    end,

    metadata = function(_, player, field)
        if not player or not player.get then return nil end
        return try(player.get, field)
    end,

    setMetadata = function(_, player, field, value)
        if not player or not player.set then return false end
        return pcall(player.set, field, value, true)
    end,

    notify = function()
        -- Nothing of its own. Bridge.notify falls through to the HUD's toast.
        return false
    end,

    isAdmin = function(_, src)
        -- ox_core leans on aces, which Bridge.isAdmin already checked before asking.
        return false
    end,

    addCommand = function()
        -- No command registry to hook; the plain RegisterCommand fallback is used.
        return false
    end,
}

-- Detection order. qb first because it is the most common and the cheapest handshake.
local ORDER = { 'qb', 'esx', 'ox' }

-- ---------------------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------------------

--- The core object, or nil. Resolved on first use rather than at load, because a framework
--- further down server.cfg has not started yet when this file runs.
function Bridge.core()
    if core then return core end

    local forced = Config.Compat and Config.Compat.forceFramework

    for _, key in ipairs(ORDER) do
        local candidate = ADAPTERS[key]
        for _, resource in ipairs(candidate.resources) do
            local wanted = (not forced) or forced == resource
            if wanted and started(resource) then
                local object = candidate.handshake(resource)
                if object then
                    core, adapter, frameworkName = object, candidate, resource
                    HUD.debug('server framework:', resource)
                    return core
                end
            end
        end
    end

    return nil
end

--- The framework's name, or 'standalone'. Printed by /hudinfo.
function Bridge.framework()
    Bridge.core()
    return frameworkName or 'standalone'
end

--- The player object for `src`, or nil. Every caller has to cope with nil: a player can drop
--- between a client event being sent and the server handling it.
function Bridge.player(src)
    local object = Bridge.core()
    if not object then return nil end
    return adapter.player(object, src)
end

--- The identifier settings are stored against, honouring Config.Persistence.scope. Returns
--- nil when the player is not loaded, and every caller treats that as "do not save yet".
function Bridge.identifier(src)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil

    if Config.Persistence.scope == 'license' then
        local license = player and adapter.license(object, player)
        if license then return license end

        for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
            if identifier:sub(1, 8) == 'license:' then return identifier end
        end
        return nil
    end

    return player and adapter.citizenId(object, player) or nil
end

--- Job name, job type and gang name for `src`. Empty strings rather than nil, so a caller
--- can index Config.JobOverrides with them without a guard.
function Bridge.roles(src)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    local roles = player and adapter.roles(object, player) or nil

    return roles or { job = '', jobType = '', gang = '' }
end

--- Whether the player is exempt from stress, by job name, job type or gang.
function Bridge.stressExempt(src)
    local roles = Bridge.roles(src)
    local exempt = Config.Stress.exemptJobs or {}

    return exempt[roles.job] == true
        or exempt[roles.jobType] == true
        or exempt['gang:' .. roles.gang] == true
end

--- Read a metadata field. nil when the framework or the player is missing, which the caller
--- distinguishes from a genuine zero.
function Bridge.metadata(src, field)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    if not player then return nil end
    return adapter.metadata(object, player, field)
end

--- Write a metadata field. Returns whether it was written, so a caller can decline to tell
--- the client that something changed when it did not.
function Bridge.setMetadata(src, field, value)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    if not player then return false end
    return adapter.setMetadata(object, player, field, value) == true
end

--- Notify a player, through the framework when it has one and through the HUD's own toast
--- when it does not.
function Bridge.notify(src, message, kind)
    local object = Bridge.core()
    if object and adapter.notify(object, src, message, kind) then return end

    TriggerClientEvent('vhud:client:Toast', src, message, kind or 'primary')
end

--- Whether `src` may run the admin commands. The console (source 0) always may.
function Bridge.isAdmin(src)
    if src == 0 then return true end

    local ace = Config.Policy.adminAce
    if ace and ace ~= '' and IsPlayerAceAllowed(src, ace) then return true end

    -- Fall back to the framework's own idea of staff, so a server that never set the ace up
    -- is not locked out of its own admin command.
    local object = Bridge.core()
    if object and adapter.isAdmin(object, src) then return true end

    return false
end

--- Register a command through the framework's command system when there is one, so it shows
--- up in the chat suggestions, and through the plain RegisterCommand when there is not.
function Bridge.addCommand(name, help, args, restricted, handler)
    if name == '' then return end

    local object = Bridge.core()
    if object and adapter.addCommand(object, name, help, args, restricted, handler) then
        return
    end

    RegisterCommand(name, function(source, rawArgs)
        if restricted and not Bridge.isAdmin(source) then
            Bridge.notify(source, L('notify.no_permission'), 'error')
            return
        end
        handler(source, rawArgs)
    end, false)
end
