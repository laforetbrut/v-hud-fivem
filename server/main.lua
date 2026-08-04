--[[
    server/main.lua

    The server side of settings: hand a player their settings when they log in, take a save
    from them, and re-validate everything on the way in.

    A client is a browser window and a browser window is not trustworthy, so nothing a client
    sends is stored as it arrived. Settings.normalise merges the payload into the schema
    (dropping keys it does not know), coerces every value, and then forces every path the
    operator locked. What comes out the far side is the only thing that is ever written.
]]

local pendingSave = {}

-- ---------------------------------------------------------------------------------------
-- Boot: what a client needs before it can draw anything
-- ---------------------------------------------------------------------------------------

--- Everything that does not change per player. Built once and reused - the theme list and
--- the status definitions are identical for everybody, and rebuilding them per login is a
--- table allocation per login for no reason.
local staticBoot
local function buildStaticBoot()
    if staticBoot then return staticBoot end

    staticBoot = {
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0',
        locale = CurrentLocale(),
        strings = LocaleTable(),
        themes = Themes.list(),
        speedometers = Speedometers.list(),
        layouts = Settings.layoutPresets(),
        refreshRates = Settings.refreshRates(),
        statuses = Config.Status,
        locked = Settings.lockedPaths(),
        -- Every choice list the menu may render, already narrowed to what this server allows.
        -- The NUI never builds a control from its own idea of what exists, so a shape or a
        -- compass the operator removed is not merely refused on save - it is not offered.
        choices = Settings.choices(),
        sharing = Config.Policy.allowSharing ~= false,
        bounds = Config.Policy.bounds,
        money = Config.Money,
        notifications = Config.Notifications,
        cinematic = Config.Cinematic,
        menu = Config.Menu,
        defaults = Settings.default(),
    }

    return staticBoot
end

--- Resolve the settings a player should be running: the newest of what they sent from KVP
--- and what the database holds, normalised, with any job override laid on top.
local function resolveSettings(src, kvpSettings, kvpTimestamp)
    local identifier = Bridge.identifier(src)
    local stored, storedAt = nil, 0

    if identifier then
        stored, storedAt = Storage.load(identifier)
    end

    local chosen
    local prefer = Config.Persistence.prefer

    if not stored then
        chosen = kvpSettings
    elseif not kvpSettings then
        chosen = stored
    elseif prefer == 'database' then
        chosen = stored
    elseif prefer == 'kvp' then
        chosen = kvpSettings
    else
        chosen = (storedAt >= (kvpTimestamp or 0)) and stored or kvpSettings
    end

    return Settings.normalise(chosen)
end

RegisterNetEvent('vhud:server:RequestBoot', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}

    local settings = resolveSettings(src, payload.settings, tonumber(payload.timestamp))
    local roles = Bridge.roles(src)

    TriggerClientEvent('vhud:client:Boot', src, {
        static = buildStaticBoot(),
        settings = settings,
        roles = roles,
        -- The client applies the job override itself and re-applies it when the job changes,
        -- so it needs the table rather than the result.
        jobOverrides = Config.JobOverrides,
        respectPlayer = Config.JobOverridesRespectPlayer,
        stress = Bridge.metadata(src, 'stress') or 0,
        hunger = Bridge.metadata(src, 'hunger') or 100,
        thirst = Bridge.metadata(src, 'thirst') or 100,
    })
end)

-- ---------------------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------------------

RegisterNetEvent('vhud:server:SaveSettings', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end

    local settings = Settings.normalise(payload.settings)
    local identifier = Bridge.identifier(src)
    if not identifier then return end

    -- Coalesce: a colour slider being dragged fires a save per frame, and without this each
    -- one would be a database round trip. The client debounces too; this is the backstop for
    -- a client that does not.
    local now = GetGameTimer()
    local previous = pendingSave[identifier]
    pendingSave[identifier] = { settings = settings, at = now }

    if previous and (now - previous.at) < Config.Persistence.debounce then return end

    SetTimeout(Config.Persistence.debounce, function()
        local entry = pendingSave[identifier]
        if not entry then return end
        pendingSave[identifier] = nil
        Storage.save(identifier, entry.settings, os.time())
    end)
end)

RegisterNetEvent('vhud:server:ResetSettings', function()
    local src = source
    local identifier = Bridge.identifier(src)
    if not identifier then return end

    pendingSave[identifier] = nil
    Storage.clear(identifier)

    TriggerClientEvent('vhud:client:ApplySettings', src, Settings.default(), true)
end)

AddEventHandler('playerDropped', function()
    local identifier = Bridge.identifier(source)
    if not identifier then return end

    -- Flush rather than drop: the player is leaving and the debounce timer will fire into a
    -- session that no longer exists.
    local entry = pendingSave[identifier]
    if entry then
        pendingSave[identifier] = nil
        Storage.save(identifier, entry.settings, os.time())
    end
end)

-- ---------------------------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------------------------

-- qb-core fires hud:client:OnMoneyChange straight at the client, so the HUD only has to
-- listen for it. What it does NOT fire is the balance readout behind /cash and /bank - those
-- lived in qb-hud, and they go away with it. Registered here only when qb-hud is not running,
-- because two resources owning one command name is a coin toss over which one answers.
local function qbHudRunning()
    local state = GetResourceState('qb-hud')
    return state == 'started' or state == 'starting'
end

CreateThread(function()
    -- One tick, so that every resource has had a chance to start before the check.
    Wait(1000)

    if qbHudRunning() then
        HUD.warn('qb-hud is still running. Stop it: two HUDs fight over the minimap, the ' ..
                 'menu key and the /cash command.')
        return
    end

    Bridge.addCommand('cash', L('command.cash'), {}, false, function(src)
        local player = Bridge.player(src)
        if not player then return end
        TriggerClientEvent('vhud:client:ShowAccount', src, 'cash', player.PlayerData.money.cash or 0)
    end)

    Bridge.addCommand('bank', L('command.bank'), {}, false, function(src)
        local player = Bridge.player(src)
        if not player then return end
        TriggerClientEvent('vhud:client:ShowAccount', src, 'bank', player.PlayerData.money.bank or 0)
    end)
end)

-- The qb-hud event, answered so that any resource still firing it keeps working.
if Config.Compat.qbHudEvents then
    RegisterNetEvent('hud:client:ShowAccounts', function(kind, amount)
        TriggerClientEvent('vhud:client:ShowAccount', source, kind, amount)
    end)
end

-- ---------------------------------------------------------------------------------------
-- The qb-hud callback
-- ---------------------------------------------------------------------------------------

-- qb-hud published `hud:server:getMenu`. Nothing in a stock qb install calls it, but a
-- third-party resource might, and an unanswered QBCore callback hangs the caller rather than
-- erroring. Answering it with the defaults costs nothing and removes the trap.
CreateThread(function()
    if not Config.Compat.qbHudCallback or qbHudRunning() then return end

    Wait(1500)

    -- Read through Bridge.field: a plain `core.Functions` raises on ox_core, whose core
    -- object is an exports table and which throws on an export that does not exist. This
    -- shim answers a callback qb-hud owned, so nil here just means there is nothing to shim.
    local functions = Bridge.field(Bridge.core(), 'Functions')
    local create = functions and functions.CreateCallback
    if not create then return end

    pcall(create, 'hud:server:getMenu', function(_, cb)
        cb(Settings.default())
    end)
end)

-- ---------------------------------------------------------------------------------------
-- Startup banner
-- ---------------------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    CreateThread(function()
        Wait(2000)
        local version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0'
        HUD.warn(('v-hud %s ready - framework: %s, database: %s, language: %s')
            :format(version, Bridge.framework(), Storage.available() and 'on' or 'off', CurrentLocale()))
    end)
end)
