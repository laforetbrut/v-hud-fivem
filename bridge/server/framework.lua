--[[
    bridge/server/framework.lua

    The server's half of the compatibility layer. Everything the server needs to know about a
    player - who they are, what job they hold, what their stress is - is asked for here, so no
    file above this one names a framework.

    qb-core is the target. qbx_core publishes the same export and the same PlayerData shape,
    so it answers here without a branch. Anything else degrades to standalone: settings still
    save to KVP on the client, stress is simply not persisted, and nothing errors.
]]

Bridge = {}

local core
local frameworkName

local function started(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

--- The core object, or nil. Resolved on first use rather than at load, because a framework
--- further down server.cfg has not started yet when this file runs.
function Bridge.core()
    if core then return core end

    for _, resource in ipairs({ 'qb-core', 'qbx_core' }) do
        if started(resource) then
            local ok, object = pcall(function()
                return exports[resource]:GetCoreObject()
            end)
            if ok and type(object) == 'table' then
                core = object
                frameworkName = resource
                HUD.debug('server framework:', resource)
                return core
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

    -- qb-core moved GetPlayer to a resource export and kept the Functions one as an alias.
    -- Try the export first so a build that dropped the alias still works.
    local ok, player = pcall(function()
        return exports['qb-core']:GetPlayer(src)
    end)
    if ok and type(player) == 'table' then return player end

    if object.Functions and object.Functions.GetPlayer then
        local ok2, player2 = pcall(object.Functions.GetPlayer, src)
        if ok2 and type(player2) == 'table' then return player2 end
    end

    return nil
end

--- The identifier settings are stored against, honouring Config.Persistence.scope. Returns
--- nil when the player is not loaded, and every caller treats that as "do not save yet".
function Bridge.identifier(src)
    local player = Bridge.player(src)

    if Config.Persistence.scope == 'license' then
        local license = player and player.PlayerData and player.PlayerData.license
        if license then return license end

        for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
            if identifier:sub(1, 8) == 'license:' then return identifier end
        end
        return nil
    end

    if player and player.PlayerData and player.PlayerData.citizenid then
        return player.PlayerData.citizenid
    end

    return nil
end

--- Job name, job type and gang name for `src`. Empty strings rather than nil, so a caller
--- can index Config.JobOverrides with them without a guard.
function Bridge.roles(src)
    local player = Bridge.player(src)
    if not player or not player.PlayerData then
        return { job = '', jobType = '', gang = '' }
    end

    local data = player.PlayerData
    return {
        job = (data.job and data.job.name) or '',
        jobType = (data.job and data.job.type) or '',
        gang = (data.gang and data.gang.name) or '',
    }
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
    local player = Bridge.player(src)
    if not player or not player.PlayerData or not player.PlayerData.metadata then return nil end
    return player.PlayerData.metadata[field]
end

--- Write a metadata field. Returns whether it was written, so a caller can decline to tell
--- the client that something changed when it did not.
function Bridge.setMetadata(src, field, value)
    local player = Bridge.player(src)
    if not player or not player.SetMetaData then return false end

    local ok = pcall(player.SetMetaData, field, value)
    return ok
end

--- Notify a player, through the framework when it has one and through the HUD's own toast
--- when it does not.
function Bridge.notify(src, message, kind)
    local object = Bridge.core()
    if object and object.Functions and object.Functions.Notify then
        if pcall(object.Functions.Notify, src, message, kind or 'primary') then return end
    end

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
    if object and object.Functions and object.Functions.HasPermission then
        local ok, allowed = pcall(object.Functions.HasPermission, src, 'admin')
        if ok and allowed then return true end
    end

    return false
end

--- Register a command through the framework's command system when there is one, so it shows
--- up in the chat suggestions, and through the plain RegisterCommand when there is not.
function Bridge.addCommand(name, help, args, restricted, handler)
    if name == '' then return end

    local object = Bridge.core()
    if object and object.Commands and object.Commands.Add then
        -- The sixth argument is a PERMISSION STRING ('admin'), not a boolean. Passing `true`
        -- there makes qb-core print a warning trace on every boot, because it tries to build
        -- an ace name out of it.
        local permission = restricted and 'admin' or nil
        local ok = pcall(object.Commands.Add, name, help, args or {}, false, handler, permission)
        if ok then return end
    end

    RegisterCommand(name, function(source, rawArgs)
        if restricted and not Bridge.isAdmin(source) then
            Bridge.notify(source, L('notify.no_permission'), 'error')
            return
        end
        handler(source, rawArgs)
    end, false)
end
