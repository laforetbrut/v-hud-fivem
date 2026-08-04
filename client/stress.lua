--[[
    client/stress.lua

    Two jobs that share a table.

    `Needs` holds the values the client cannot compute for itself - hunger, thirst, stress and
    anything an operator added to Config.Status with source = 'metadata'. They arrive by event
    from the server or the framework and are held here until the HUD tick reads them.

    The rest is stress: asking the server for a change when the player shoots or speeds, and
    drawing the screen effects when it is high. The client never sets its own stress. It asks,
    and the server decides - a client that could set its own stress could set it to zero, and
    then the whole mechanic is decorative.
]]

Needs = {
    hunger = 100,
    thirst = 100,
    stress = 0,
    -- Custom metadata gauges from Config.Status, by key.
    custom = {},
}

--- Seed from the boot payload so the gauges are right on the first frame rather than after
--- the first metadata event, which may be minutes away.
function Needs.seed(hunger, thirst, stress)
    Needs.hunger = tonumber(hunger) or Needs.hunger
    Needs.thirst = tonumber(thirst) or Needs.thirst
    Needs.stress = tonumber(stress) or Needs.stress
end

--- Read a metadata-sourced status. Falls back to the framework's own player data, so a
--- gauge an operator added works without anybody firing an event for it.
function Needs.metadata(field)
    if Needs.custom[field] ~= nil then return Needs.custom[field] end

    local data = Compat.playerData()
    local value = data.metadata and data.metadata[field]
    return tonumber(value) or 0
end

RegisterNetEvent('vhud:client:UpdateNeeds', function(hunger, thirst)
    Needs.hunger = tonumber(hunger) or Needs.hunger
    Needs.thirst = tonumber(thirst) or Needs.thirst
end)

--[[
    ESX keeps hunger and thirst in esx_status, not in the player object.

    esx_status is a client-side module that ticks its own values and broadcasts them; there is
    no metadata table to read and no server event to wait for. So it is listened to directly.

    Its scale is 0-1000000, not 0-100. `percent` is present on modern builds and already a
    percentage; `val` is the raw counter. Both are handled because forks differ, and a value
    over 100 is taken as the raw scale - a percentage cannot exceed it.

    On a qb-core server this listener simply never fires.
]]
for _, event in ipairs({ 'esx_status:onTick', 'esx_status:update' }) do
    AddEventHandler(event, function(statuses)
        if type(statuses) ~= 'table' then return end

        for _, status in pairs(statuses) do
            local name = type(status) == 'table' and (status.name or status.getName) or nil
            local raw = type(status) == 'table' and (status.percent or status.val) or nil
            local value = tonumber(raw)

            if type(name) == 'string' and value then
                if value > 100 then value = value / 10000 end
                value = HUD.clamp(value, 0, 100, nil)

                if value then
                    if name == 'hunger' then Needs.hunger = value
                    elseif name == 'thirst' then Needs.thirst = value
                    elseif name == 'stress' then Needs.stress = value
                    else Needs.custom[name] = value end
                end
            end
        end
    end)
end

RegisterNetEvent('vhud:client:UpdateStress', function(stress)
    Needs.stress = HUD.clamp(stress, 0, 100, Needs.stress)
end)

RegisterNetEvent('vhud:client:UpdateStatus', function(key, value)
    if type(key) ~= 'string' then return end
    Needs.custom[key] = HUD.clamp(value, 0, 100, 0)
end)

-- The qb-hud names. qb-core, qb-ambulancejob and qb-smallresources all fire these, and none
-- of them are going to be edited.
if Config.Compat.qbHudEvents then
    RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst)
        Needs.hunger = tonumber(hunger) or Needs.hunger
        Needs.thirst = tonumber(thirst) or Needs.thirst
    end)

    RegisterNetEvent('hud:client:UpdateStress', function(stress)
        Needs.stress = HUD.clamp(stress, 0, 100, Needs.stress)
    end)
end

-- The framework pushes the whole player object on any change; metadata moves with it.
RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, value)
    if key ~= 'all' or type(value) ~= 'table' then return end
    local metadata = value.metadata
    if type(metadata) ~= 'table' then return end

    Needs.hunger = tonumber(metadata.hunger) or Needs.hunger
    Needs.thirst = tonumber(metadata.thirst) or Needs.thirst
    Needs.stress = tonumber(metadata.stress) or Needs.stress
end)

-- ---------------------------------------------------------------------------------------
-- The stomach growl
-- ---------------------------------------------------------------------------------------

--[[
    Hunger and thirst arrive through five different events, so the crossing is detected by
    SAMPLING the value rather than by hooking each handler - one watcher covers every path,
    including a future sixth one.

    The detector is per need and per threshold, and it is edge-triggered on the way DOWN:

      * armed[t] starts true. Falling to or below t fires and disarms t.
      * t re-arms only once the value climbs back above t + rearm.

    So starving at 4% is silent, eating back to 60% and starving again growls afresh, and a
    value oscillating on the line does not growl every tick.
]]

Growl = {}

local growlState = {
    hunger = {},
    thirst = {},
    last = 0,
    seeded = false,
}

--- Thresholds, highest first, so a single big drop fires the HIGHEST one crossed rather than
--- all three at once. Sorted here because the operator writes them in whatever order.
local function growlThresholds()
    local out = {}
    for _, value in ipairs(Config.Alerts.growl.thresholds or {}) do
        local number = tonumber(value)
        if number then out[#out + 1] = number end
    end
    table.sort(out, function(a, b) return a > b end)
    return out
end

local sortedThresholds

local function playGrowl()
    local rules = Config.Alerts.growl
    local now = GetGameTimer()

    -- One growl at a time, whichever need triggered it. Hunger and thirst usually run out
    -- together, and two overlapping growls sound like a bug.
    if (now - growlState.last) < (rules.cooldown or 0) then return false end
    growlState.last = now

    if State.settings and not State.settings.advanced.sounds then return false end

    if rules.useGameSound then
        Compat.playFrontendSound(rules.sound, rules.set)
    else
        SendNUIMessage({
            action = 'growl',
            seconds = rules.seconds or 3.5,
            volume = rules.volume or 0.5,
        })
    end

    return true
end

--- Forget every crossing. Used by the tests, and by anything that needs the detector to treat
--- the next sample as a fresh start rather than as a continuation.
function Growl.reset()
    growlState.hunger, growlState.thirst = {}, {}
    growlState.last, growlState.seeded = 0, false
    sortedThresholds = growlThresholds()
end

--- Look at one need and fire if it just crossed a threshold downward.
function Growl.check(key, value)
    local rules = Config.Alerts.growl
    local armed = growlState[key]
    sortedThresholds = sortedThresholds or growlThresholds()

    for _, threshold in ipairs(sortedThresholds) do
        if armed[threshold] == nil then armed[threshold] = true end

        if value > (threshold + (rules.rearm or 0)) then
            armed[threshold] = true
        elseif value <= threshold and armed[threshold] then
            -- Disarm whatever fired OR not: a growl suppressed by the cooldown must still
            -- count as handled, or it retries every tick until the cooldown lapses and then
            -- growls for a crossing that happened ten seconds ago.
            armed[threshold] = false
            playGrowl()
            return
        end
    end
end

if Config.Alerts and Config.Alerts.growl and Config.Alerts.growl.enabled then
    sortedThresholds = growlThresholds()

    CreateThread(function()
        while true do
            Wait(1000)

            if State.ready and LocalPlayer.state.isLoggedIn then
                -- The first pass only records where the player already is. Without it, logging
                -- in already starving growls immediately - which is a crossing that happened
                -- before the session started.
                if not growlState.seeded then
                    growlState.seeded = true
                    for _, threshold in ipairs(sortedThresholds) do
                        growlState.hunger[threshold] = Needs.hunger > threshold
                        growlState.thirst[threshold] = Needs.thirst > threshold
                    end
                else
                    Growl.check('hunger', Needs.hunger)
                    Growl.check('thirst', Needs.thirst)
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------------------
-- Gaining stress
-- ---------------------------------------------------------------------------------------

local function requestGain(amount)
    TriggerServerEvent('vhud:server:GainStress', amount)
end

local function randomIn(range)
    return math.random(range.min, range.max)
end

if Config.Stress.enabled then
    -- Speeding.
    CreateThread(function()
        while true do
            Wait(Config.Stress.speedInterval)

            if State.ready and LocalPlayer.state.isLoggedIn then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)

                if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                    local class = GetVehicleClass(vehicle)
                    local model = GetEntityModel(vehicle)

                    if Config.Stress.vehicleClasses[class] and not Config.Stress.exemptVehicles[model] then
                        local units = (State.settings and State.settings.units == 'mph') and 2.236936 or 3.6
                        local speed = GetEntitySpeed(vehicle) * units
                        local belt = Compat.vehicleState(vehicle)

                        -- A motorcycle has no seatbelt to fasten, so it is always held to the
                        -- buckled threshold rather than punished for something impossible.
                        local threshold = (class == 8 or belt.on)
                            and Config.Stress.speedBuckled
                            or Config.Stress.speedUnbuckled

                        if speed >= threshold then
                            requestGain(randomIn(Config.Stress.speedAmount))
                        end
                    end
                end
            end
        end
    end)

    -- Shooting.
    CreateThread(function()
        while true do
            Wait(500)

            if State.ready and LocalPlayer.state.isLoggedIn then
                local ped = PlayerPedId()

                if IsPedShooting(ped) then
                    local weapon = GetSelectedPedWeapon(ped)

                    if not Config.Stress.exemptWeapons[weapon]
                        and math.random() < Config.Stress.shootingChance then
                        requestGain(randomIn(Config.Stress.shootingAmount))
                    end
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------------------
-- Screen effects
-- ---------------------------------------------------------------------------------------

--- The effect band the current stress falls into, or nil when it is below the floor.
local function bandFor(stress)
    if stress < Config.Stress.effectMinimum then return nil end

    for _, band in ipairs(Config.Stress.effects) do
        if stress >= band.min and stress < band.max then return band end
    end

    -- Fall back UPWARD only.
    --
    -- Returning the last band unconditionally handed the most violent effect to a stress of
    -- zero whenever the bands did not cover the value - a gap between two bands, or a floor
    -- raised above the lowest band's min. The last band is right only for a value ABOVE it.
    local last = Config.Stress.effects[#Config.Stress.effects]
    return (last and stress >= last.min) and last or nil
end

CreateThread(function()
    while true do
        -- Gated on Config.Stress.enabled like the gain threads above it. Without that check
        -- this loop kept evaluating bands - and could still shake the camera and blur the
        -- screen - on a server that had switched the whole stress mechanic off.
        local band = Config.Stress.enabled and State.ready and bandFor(Needs.stress) or nil

        if not band then
            Wait(1000)
        else
            -- The interval is a range so that two players at the same stress level do not
            -- blur in lockstep, which looks scripted rather than unsettling.
            Wait(math.random(band.interval[1], band.interval[2]))

            if State.ready and bandFor(Needs.stress) then
                local ped = PlayerPedId()

                if not IsEntityDead(ped) and not IsPauseMenuActive() then
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', band.shake)

                    -- The blur is a pair of timecycle transitions rather than one, so it eases
                    -- in and back out instead of snapping.
                    SetTimecycleModifier('damage')
                    SetTimecycleModifierStrength(0.4)
                    Wait(band.blur)
                    ClearTimecycleModifier()
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------

--- Ask the server for a stress change from another client resource. The server still decides.
exports('AddStress', function(amount) TriggerServerEvent('vhud:server:GainStress', amount) end)
exports('RemoveStress', function(amount) TriggerServerEvent('vhud:server:RelieveStress', amount) end)

--- The values the HUD is currently drawing, for a resource that wants them without repeating
--- the metadata plumbing.
exports('GetNeeds', function()
    return {
        hunger = Needs.hunger,
        thirst = Needs.thirst,
        stress = Needs.stress,
    }
end)
