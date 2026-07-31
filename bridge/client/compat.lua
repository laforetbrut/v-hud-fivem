--[[
    bridge/client/compat.lua

    Everything this HUD asks of another resource goes through here, behind a `Compat.*`
    function. Nothing above this file knows the name of a fuel script, a voice script or an
    inventory, which is what lets a server swap any of them without editing the HUD.

    Two rules govern every provider in this file:

      * Detection is at runtime, on first use, and cached. `GetResourceState` at load is not
        enough - a resource further down server.cfg has not started yet when this file runs.
      * A missing provider degrades, never errors. The fail direction is chosen per function
        and written down at each one, because the right answer differs: fuel falls back to
        the engine's own tank so the gauge keeps moving, while the harness check fails closed
        so a ring never lights for an item nobody has.
]]

Compat = {}

-- What was picked for each capability, filled in on first use. Also what `/hudinfo` prints,
-- which is the fastest way to answer "why is my fuel gauge stuck at 100".
Compat.provider = {
    fuel = nil,
    voice = nil,
    notify = nil,
    sounds = nil,
    inventory = nil,
    framework = nil,
}

local function started(resource)
    if not resource or resource == '' then return false end
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

--- Call `method` on `resource`'s export table, returning nil instead of raising when the
--- resource is gone, the export is not published, or the call itself throws. Every export
--- this resource makes to somebody else's code goes through here.
local function callExport(resource, method, ...)
    if not method or not started(resource) then return nil end

    local ok, result = pcall(function(...)
        return exports[resource][method](exports[resource], ...)
    end, ...)

    if not ok then return nil end
    return result
end

-- ---------------------------------------------------------------------------------------
-- Framework
-- ---------------------------------------------------------------------------------------

local core

--- The qb-core object, or nil on a server that has none. Cached after the first successful
--- call. qbx_core publishes the same export, so both answer here without a branch.
function Compat.core()
    if core then return core end

    for _, resource in ipairs({ 'qb-core', 'qbx_core' }) do
        if started(resource) then
            local ok, object = pcall(function()
                return exports[resource]:GetCoreObject()
            end)
            if ok and type(object) == 'table' then
                core = object
                Compat.provider.framework = resource
                HUD.debug('framework:', resource)
                return core
            end
        end
    end

    return nil
end

--- Player data, or an empty table. Callers treat a missing field as "not known yet" rather
--- than as zero, so an empty table here is a safe answer during the login window.
function Compat.playerData()
    local object = Compat.core()
    if not object or not object.Functions or not object.Functions.GetPlayerData then return {} end

    local ok, data = pcall(object.Functions.GetPlayerData)
    return (ok and type(data) == 'table') and data or {}
end

-- ---------------------------------------------------------------------------------------
-- Fuel
-- ---------------------------------------------------------------------------------------

local fuelProvider
local fuelResolved = false

--- Work out which fuel script is running, once. Honours Config.Compat.forceFuel first so an
--- operator can skip detection on a server where two fuel scripts are installed and only one
--- is actually in charge.
local function resolveFuel()
    if fuelResolved then return fuelProvider end

    local forced = Config.Compat.forceFuel
    for _, entry in ipairs(Config.Compat.fuel) do
        local isForced = forced and entry.resource == forced
        if (forced and isForced) or (not forced and (entry.kind == 'native' or started(entry.resource))) then
            -- An export provider has to actually answer before it is accepted. A resource can
            -- be started and still not publish the export - that is the case this catches,
            -- and without it the gauge would sit at zero forever with no clue why.
            if entry.kind ~= 'export' or callExport(entry.resource, entry.percent, GetVehiclePedIsIn(PlayerPedId(), false)) ~= nil then
                fuelProvider = entry
                fuelResolved = true
                Compat.provider.fuel = entry.resource
                HUD.debug('fuel provider:', entry.resource)
                return fuelProvider
            end
        end
    end

    -- Nothing answered. The native entry is last in the shipped list and always works, so
    -- reaching here means the operator removed it; synthesise it rather than return nil.
    fuelProvider = { resource = 'native', kind = 'native' }
    fuelResolved = true
    Compat.provider.fuel = 'native'
    return fuelProvider
end

--- Fuel as a percentage, 0-100. Fails OPEN: an unreadable tank reads full rather than empty,
--- because a gauge stuck at zero makes a player think they have broken down.
function Compat.fuel(vehicle)
    if not vehicle or vehicle == 0 then return 100 end

    local provider = resolveFuel()

    if provider.kind == 'export' then
        local value = callExport(provider.resource, provider.percent, vehicle)
        if type(value) == 'number' then return HUD.clamp(value, 0, 100, 100) end
    elseif provider.kind == 'statebag' then
        local state = Entity(vehicle).state
        local value = state and state[provider.bag]
        if type(value) == 'number' then return HUD.clamp(value, 0, 100, 100) end
    end

    return HUD.clamp(GetVehicleFuelLevel(vehicle), 0, 100, 100)
end

--- Remaining range, in the provider's own unit, or nil when it cannot say. Only rcore_fuel
--- publishes this today; every other provider returns nil and the readout is hidden rather
--- than shown as a zero.
function Compat.fuelRange(vehicle)
    if not Config.Compat.showRange or not vehicle or vehicle == 0 then return nil end

    local provider = resolveFuel()
    if provider.kind ~= 'export' or not provider.range then return nil end

    local value = callExport(provider.resource, provider.range, vehicle)
    return type(value) == 'number' and math.floor(value) or nil
end

--- Litres in the tank, or nil. Same story as the range.
function Compat.fuelLitres(vehicle)
    if not vehicle or vehicle == 0 then return nil end

    local provider = resolveFuel()
    if provider.kind ~= 'export' or not provider.litres then return nil end

    local value = callExport(provider.resource, provider.litres, vehicle)
    return type(value) == 'number' and value or nil
end

--- Tank capacity in litres, or nil.
function Compat.fuelCapacity(vehicle)
    if not vehicle or vehicle == 0 then return nil end

    local provider = resolveFuel()
    if provider.kind ~= 'export' or not provider.capacity then return nil end

    local value = callExport(provider.resource, provider.capacity, vehicle)
    return type(value) == 'number' and value or nil
end

-- ---------------------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------------------

local notifyProvider

local function resolveNotify()
    if notifyProvider then return notifyProvider end

    local forced = Config.Compat.forceNotify
    local candidates = forced and { forced } or Config.Compat.notify

    for _, resource in ipairs(candidates) do
        if resource == 'native' or started(resource) then
            notifyProvider = resource
            Compat.provider.notify = resource
            return notifyProvider
        end
    end

    notifyProvider = 'native'
    Compat.provider.notify = 'native'
    return notifyProvider
end

--- Show `message`. `kind` is 'primary', 'success' or 'error'. Silent when the player has
--- turned HUD notifications off, except for the ones the caller marks as forced.
---
--- On a stock QBCore server the notifications are qb-core's, not this resource's: they go to
--- qb-core's own NUI page and keep its hardcoded look. `Config.Notifications.own` decides
--- whether the messages THIS resource raises are drawn in the player's theme instead, which
--- is the only half of the problem a HUD can fix from the outside.
function Compat.notify(message, kind, forced, duration)
    if not message or message == '' then return end
    if not forced and State and State.settings and not State.settings.advanced.notifications then
        return
    end

    kind = kind or 'primary'

    if Config.Notifications.own then
        SendNUIMessage({ action = 'toast', message = message, kind = kind, duration = duration })
        if Config.Notifications.sound then Compat.playSound('click', 0.05) end
        return
    end

    local provider = resolveNotify()

    if provider == 'ox_lib' then
        local types = { primary = 'inform', success = 'success', error = 'error' }
        if pcall(function()
                exports.ox_lib:notify({ description = message, type = types[kind] or 'inform' })
            end) then
            return
        end
    elseif provider == 'okokNotify' then
        local titles = { primary = 'Info', success = 'OK', error = 'Erreur' }
        if pcall(function()
                exports['okokNotify']:Alert(titles[kind] or 'Info', message, 4000, kind)
            end) then
            return
        end
    else
        local object = Compat.core()
        if object and object.Functions and object.Functions.Notify then
            if pcall(object.Functions.Notify, message, kind) then return end
        end
    end

    -- Last resort, and the reason this function can be called from anywhere: the HUD draws
    -- its own toast, so a server with no notification resource at all still gets told things.
    SendNUIMessage({ action = 'toast', message = message, kind = kind, duration = duration })
end

-- Mirror qb-core's notifications into the HUD's theme.
--
-- Off by default, and the comment in config.lua explains why: qb-core will still draw its
-- own, so one event becomes two notifications unless the operator also comments out the
-- SendNUIMessage in qb-core/client/functions.lua. That edit is theirs to make; this resource
-- will not reach into another one to silence it.
if Config.Notifications.mirrorQbCore then
    RegisterNetEvent('QBCore:Notify', function(text, kind, length)
        if type(text) == 'table' then text = text.text or text.caption end
        if type(text) ~= 'string' then return end

        SendNUIMessage({
            action = 'toast',
            message = text,
            kind = kind or 'primary',
            duration = tonumber(length),
        })
    end)
end

--- The themed toast, for another resource. `exports['v-hud']:Notify('Hello', 'success')`.
exports('Notify', function(message, kind, duration)
    Compat.notify(message, kind, true, tonumber(duration))
end)

-- ---------------------------------------------------------------------------------------
-- Sounds
-- ---------------------------------------------------------------------------------------

local soundProvider
local soundResolved = false

local function resolveSounds()
    if soundResolved then return soundProvider end
    soundResolved = true

    for _, resource in ipairs(Config.Compat.sounds or {}) do
        if started(resource) then
            soundProvider = resource
            Compat.provider.sounds = resource
            return soundProvider
        end
    end

    return nil
end

--- Play a menu sound, if the player wants sounds and a sound resource exists. Doing nothing
--- is a perfectly good outcome here, which is why there is no fallback.
function Compat.playSound(name, volume)
    if State and State.settings and not State.settings.advanced.sounds then return end

    local provider = resolveSounds()
    if not provider then return end

    TriggerServerEvent('InteractSound_SV:PlayOnSource', name, volume or 0.1)
end

--- Play one of the game's own frontend sounds. Unlike Compat.playSound this needs no sound
--- resource at all - the samples ship with GTA - which is what makes it the right choice for
--- the driving warnings, where a server with no InteractSound would otherwise get silence.
---
--- Honours the player's sound setting for the same reason everything else does: a HUD that
--- keeps beeping after you turned its sounds off is a HUD you delete.
function Compat.playFrontendSound(name, set)
    if not name or name == '' then return end
    if State and State.settings and not State.settings.advanced.sounds then return end

    PlaySoundFrontend(-1, name, set or '', true)
end

-- ---------------------------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------------------------

local inventoryProvider
local inventoryResolved = false

local function resolveInventory()
    if inventoryResolved then return inventoryProvider end
    inventoryResolved = true

    local forced = Config.Compat.forceInventory
    local candidates = forced and { forced } or Config.Compat.inventory

    for _, resource in ipairs(candidates) do
        if started(resource) then
            inventoryProvider = resource
            Compat.provider.inventory = resource
            HUD.debug('inventory:', resource)
            return inventoryProvider
        end
    end

    return nil
end

--- Whether the player is carrying `item`. Fails CLOSED - an inventory that cannot be read
--- reports "no", because the only thing this drives is the harness ring and a ring that
--- lights for an item nobody has is worse than one that never lights.
function Compat.hasItem(item)
    if not item then return false end

    -- The framework's own player data is the cheapest read and covers qb-inventory,
    -- ps-inventory and every fork that keeps writing PlayerData.items.
    local data = Compat.playerData()
    if type(data.items) == 'table' then
        for _, entry in pairs(data.items) do
            if type(entry) == 'table' and entry.name == item and (entry.amount or 1) > 0 then
                return true
            end
        end
    end

    local provider = resolveInventory()
    if not provider then return false end

    if provider == 'ox_inventory' then
        local ok, count = pcall(function()
            return exports.ox_inventory:Search('count', item)
        end)
        return ok and type(count) == 'number' and count > 0
    end

    for _, method in ipairs({ 'HasItem', 'hasItem' }) do
        local result = callExport(provider, method, item)
        if type(result) == 'boolean' then return result end
        if type(result) == 'number' then return result > 0 end
    end

    return false
end

-- ---------------------------------------------------------------------------------------
-- Voice
-- ---------------------------------------------------------------------------------------

local voiceProvider
local voiceResolved = false

local function resolveVoice()
    if voiceResolved then return voiceProvider end
    voiceResolved = true

    local forced = Config.Compat.forceVoice
    local candidates = forced and { forced } or Config.Compat.voice

    for _, resource in ipairs(candidates) do
        if started(resource) then
            voiceProvider = resource
            Compat.provider.voice = resource
            HUD.debug('voice:', resource)
            return voiceProvider
        end
    end

    return nil
end

-- pma-voice publishes the radio state as an event rather than a readable value, so it is
-- latched here and read back by Compat.voice.
local radioActive = false
local radioChannel = 0

AddEventHandler('pma-voice:radioActive', function(active)
    radioActive = active == true
end)

AddEventHandler('pma-voice:setTalkingMode', function(mode)
    if type(mode) == 'number' then LocalPlayer.state.vhudVoiceMode = mode end
end)

--- Voice range 1-3, whether the player is talking, and the radio channel. Works with no voice
--- resource at all: range reads 0 and the indicator stays dim.
function Compat.voice()
    local provider = resolveVoice()
    local playerId = PlayerId()
    local talking = NetworkIsPlayerTalking(playerId)

    local range = 0
    local proximity = LocalPlayer.state and LocalPlayer.state['proximity']
    if type(proximity) == 'table' and proximity.distance then
        range = proximity.distance
    elseif type(LocalPlayer.state.vhudVoiceMode) == 'number' then
        range = LocalPlayer.state.vhudVoiceMode
    end

    local channel = radioChannel
    if provider == 'pma-voice' then
        channel = LocalPlayer.state and LocalPlayer.state['radioChannel'] or 0
    end

    return {
        provider = provider,
        range = range,
        talking = talking,
        radio = channel or 0,
        radioActive = radioActive,
    }
end

-- ---------------------------------------------------------------------------------------
-- Seatbelt, cruise control and nitrous
-- ---------------------------------------------------------------------------------------

-- These are latched here rather than in client/vehicle.lua so that adding a resource's event
-- name to Config.Compat is genuinely the only change needed to support it.

local belt = { on = false, cruise = false, nitro = 0, nitroActive = false, harnessHp = 20 }

for _, event in ipairs(Config.Compat.seatbeltEvents or {}) do
    AddEventHandler(event, function(value)
        -- Some scripts pass the new state, others toggle. A boolean argument is taken as the
        -- state; anything else means toggle.
        if type(value) == 'boolean' then belt.on = value else belt.on = not belt.on end
    end)
    RegisterNetEvent(event)
end

for _, event in ipairs(Config.Compat.cruiseEvents or {}) do
    AddEventHandler(event, function(value)
        if type(value) == 'boolean' then belt.cruise = value else belt.cruise = not belt.cruise end
    end)
    RegisterNetEvent(event)
end

for _, event in ipairs(Config.Compat.nitroEvents or {}) do
    AddEventHandler(event, function(level, active)
        belt.nitro = tonumber(level) or 0
        belt.nitroActive = active and true or false
    end)
    RegisterNetEvent(event)
end

RegisterNetEvent('hud:client:UpdateHarness', function(hp)
    belt.harnessHp = tonumber(hp) or 0
end)

RegisterNetEvent('vhud:client:UpdateHarness', function(hp)
    belt.harnessHp = tonumber(hp) or 0
end)

--- The latched vehicle state. `vehicle` is used to read the state bags some scripts publish
--- instead of firing an event: the seatbelt state, and jim-mechanic's per-vehicle NOS.
function Compat.vehicleState(vehicle)
    local bagName = Config.Compat.seatbeltStateBag
    if bagName and vehicle and vehicle ~= 0 then
        local state = LocalPlayer.state and LocalPlayer.state[bagName]
        if type(state) == 'boolean' then belt.on = state end
    end

    -- jim-mechanic keeps `hasnitro` and `noslevel` on the vehicle entity. The bag only
    -- refreshes on a save, so an event that arrives later overrides this; the bag's job is
    -- the first frame in a NOS-fitted car, before anything has fired.
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local entityState = Entity(vehicle).state
        if entityState then
            local fitted = nil
            for _, bag in ipairs(Config.Compat.nitroHasBags or {}) do
                local value = entityState[bag]
                if value ~= nil then
                    fitted = value == true or value == 1
                    break
                end
            end

            for _, bag in ipairs(Config.Compat.nitroStateBags or {}) do
                local value = entityState[bag]
                if type(value) == 'number' then
                    -- An event wins over the bag while a boost is live: the event moves per
                    -- use, the bag per save.
                    if not belt.nitroActive then belt.nitro = HUD.clamp(value, 0, 100, 0) end
                    if fitted == nil then fitted = value > 0 end
                    break
                end
            end

            if fitted == false then
                belt.nitro = 0
                belt.nitroActive = false
            end
        end
    end

    return belt
end

--- Reset on leaving a vehicle. A belt that stays fastened after you get out is the single
--- most reported HUD bug there is.
function Compat.resetVehicleState()
    belt.on = false
    belt.cruise = false
    belt.nitro = 0
    belt.nitroActive = false
end

-- ---------------------------------------------------------------------------------------
-- Getting out of the way
-- ---------------------------------------------------------------------------------------

-- Resources that answered their "am I open" export at least once. A resource that does not
-- publish one is recorded as unusable and never asked again: this runs on the HUD tick, and
-- a pcall that always fails is a pcall that always costs.
local overlayChecked = {}
local lastOverlay = 0

-- The game puts up more than one kind of full-screen thing, and only ONE of them answers to
-- IsPauseMenuActive(). The "do you really want to quit" box (Alt+F4, and the Quit entry in the
-- pause menu) is a frontend WARNING MESSAGE - a different screen, drawn by a different scaleform,
-- with the pause menu already closed behind it. That is why the HUD stayed on screen over it.
--
-- Each entry is looked up rather than called directly: a native missing on an older build would
-- otherwise take the whole tick down, and this runs every frame.
local frontendChecks = {}

for _, name in ipairs({
    'IsWarningMessageActive',   -- quit prompt, "unsaved progress", store warnings
    'IsPlayerSwitchInProgress', -- the character switch fly-over
}) do
    -- _G[name] rather than rawget: some Cfx Lua runtimes bind natives lazily through a
    -- metatable, and a raw read would find nothing and silently skip the check.
    local fn = _G[name]
    if type(fn) == 'function' then frontendChecks[#frontendChecks + 1] = fn end
end

--- Whether something is on screen that the HUD should get out from under: the pause menu, a
--- loading screen, another resource's NUI, or a resource that says it is open.
---
--- None of this reaches into another resource. It reads the pause menu from the game, focus
--- from the client, and asks each configured resource a question it already answers.
function Compat.overlayOpen()
    local hide = Config.HideWhen

    if hide.pauseMenu and (IsPauseMenuActive() or GetIsLoadingScreenActive()) then
        lastOverlay = GetGameTimer()
        return true
    end

    if hide.frontend then
        for i = 1, #frontendChecks do
            if frontendChecks[i]() then
                lastOverlay = GetGameTimer()
                return true
            end
        end
    end

    -- Focus held by anything that is not this resource's own menu.
    if hide.nuiFocus and IsNuiFocused() and not (State and (State.menuOpen or State.layoutMode)) then
        lastOverlay = GetGameTimer()
        return true
    end

    for _, entry in ipairs(hide.resources or {}) do
        if overlayChecked[entry.resource] ~= false and started(entry.resource) then
            local ok, open = pcall(function()
                return exports[entry.resource][entry.export](exports[entry.resource])
            end)

            if not ok then
                -- No such export on this build. Stop asking.
                overlayChecked[entry.resource] = false
            else
                overlayChecked[entry.resource] = true
                if open == true then
                    lastOverlay = GetGameTimer()
                    return true
                end
            end
        end
    end

    -- A short tail, so the HUD does not flash back for one frame between two menus.
    return (GetGameTimer() - lastOverlay) < (hide.linger or 0)
end

-- ---------------------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------------------

--- Everything that was detected, for `/hudinfo`. Resolves each capability first so that the
--- command reports what WOULD be used, not only what happened to be used already.
function Compat.report()
    resolveFuel()
    resolveNotify()
    resolveSounds()
    resolveInventory()
    resolveVoice()
    Compat.core()

    return {
        framework = Compat.provider.framework or 'none',
        fuel = Compat.provider.fuel or 'none',
        voice = Compat.provider.voice or 'none',
        notify = Compat.provider.notify or 'none',
        sounds = Compat.provider.sounds or 'none',
        inventory = Compat.provider.inventory or 'none',
    }
end
