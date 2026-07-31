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

    return Config.Stress.effects[#Config.Stress.effects]
end

CreateThread(function()
    while true do
        local band = State.ready and bandFor(Needs.stress) or nil

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
