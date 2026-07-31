--[[
    client/vehicle.lua

    Everything the speedometer draws, collected in one place.

    Fuel is the only reading here that is not free. Every other value is a native that costs
    nothing, but a fuel export is a call into another resource, so it is throttled to
    Config.Compat.fuelInterval and cached in between. The cache is per vehicle: without that,
    stepping out of a full car into an empty one shows a full tank for two seconds.
]]

Vehicle = {}

local fuelCache = { vehicle = 0, percent = 100, range = nil, at = 0 }

--- Fuel percentage and remaining range for `vehicle`, re-read at most every fuelInterval.
local function fuel(vehicle)
    local now = GetGameTimer()

    if fuelCache.vehicle ~= vehicle then
        fuelCache.vehicle = vehicle
        fuelCache.at = 0
    end

    if (now - fuelCache.at) >= Config.Compat.fuelInterval then
        fuelCache.at = now
        fuelCache.percent = Compat.fuel(vehicle)
        fuelCache.range = Compat.fuelRange(vehicle)
    end

    return fuelCache.percent, fuelCache.range
end

--- Engine health as 0-100. The native returns 0-1000 and returns NaN on a vehicle the client
--- does not own yet; NaN is the only value not equal to itself, which is how it is caught.
local function engineHealth(vehicle)
    local health = GetVehicleEngineHealth(vehicle)
    if health ~= health then return 0 end
    return HUD.clamp(health / 10.0, 0, 100, 0)
end

--- Gear as a short string. Reverse and neutral read better as letters than as 0 and -1.
local function gear(vehicle)
    local current = GetVehicleCurrentGear(vehicle)

    if IsVehicleInBurnout(vehicle) then return 'B' end
    if current == 0 then
        -- Gear 0 is neutral standing still and reverse when moving backwards. The engine does
        -- not distinguish them, so the direction of travel does.
        return GetEntitySpeedVector(vehicle, true).y < -0.5 and 'R' or 'N'
    end

    return tostring(current)
end

--- Indicator and light state. Both natives return through out-parameters, and both are
--- wrapped because a vehicle handle can die between the check and the call.
local function lights(vehicle)
    local ok, lightsOn, highBeams = pcall(GetVehicleLightsState, vehicle)
    local left, right = false, false

    local okIndicators, indicatorState = pcall(GetVehicleIndicatorLights, vehicle)
    if okIndicators and type(indicatorState) == 'number' then
        -- 0 none, 1 left, 2 right, 3 both (hazards).
        left = indicatorState == 1 or indicatorState == 3
        right = indicatorState == 2 or indicatorState == 3
    end

    return {
        on = ok and lightsOn == 1,
        high = ok and highBeams == 1,
        left = left,
        right = right,
    }
end

--- Everything the speedometer needs for `vehicle`, or nil when there is no vehicle.
function Vehicle.read(vehicle, settings)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local multiplier = settings.units == 'mph' and 2.236936 or 3.6
    local speed = GetEntitySpeed(vehicle) * multiplier
    local fuelPercent, range = fuel(vehicle)
    local belt = Compat.vehicleState(vehicle)
    local ped = PlayerPedId()

    local isAircraft = IsPedInAnyHeli(ped) or IsPedInAnyPlane(ped)

    return {
        speed = math.floor(speed + 0.5),
        maxSpeed = math.floor(GetVehicleEstimatedMaxSpeed(vehicle) * multiplier + 0.5),
        rpm = GetVehicleCurrentRpm(vehicle),
        gear = gear(vehicle),
        fuel = math.floor(fuelPercent + 0.5),
        range = range,
        engine = math.floor(engineHealth(vehicle) + 0.5),
        seatbelt = belt.on,
        cruise = belt.cruise,
        nitro = belt.nitro,
        nitroActive = belt.nitroActive,
        harness = belt.harnessHp,
        hasHarness = Vehicle.harness,
        lights = lights(vehicle),
        aircraft = isAircraft,
        altitude = isAircraft and math.floor(GetEntityCoords(ped).z * 0.5) or nil,
        -- A bicycle has no engine, no fuel and no gears; the NUI hides those readouts rather
        -- than drawing three zeros.
        bicycle = IsThisModelABicycle(GetEntityModel(vehicle)),
        driver = GetPedInVehicleSeat(vehicle, -1) == ped,
    }
end

-- ---------------------------------------------------------------------------------------
-- The harness item
-- ---------------------------------------------------------------------------------------

Vehicle.harness = false

CreateThread(function()
    while true do
        Wait(Config.Tick.inventory)

        if State.ready and State.settings and State.settings.show.harness then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                Vehicle.harness = Compat.hasItem(Config.Compat.harnessItem)
            else
                Vehicle.harness = false
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Low fuel warning
-- ---------------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(10000)

        local settings = State.settings
        if settings and settings.advanced.lowFuel then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0
                and GetPedInVehicleSeat(vehicle, -1) == ped
                and not IsThisModelABicycle(GetEntityModel(vehicle))
                and Compat.fuel(vehicle) <= Config.Compat.lowFuelAt then

                Compat.notify(L('notify.low_fuel'), 'error')
                Compat.playSound('pager', 0.1)
                Wait(Config.Compat.lowFuelRepeat)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Leaving a vehicle
-- ---------------------------------------------------------------------------------------

-- A belt that stays fastened after you get out is the single most reported HUD bug there is.
-- Watching the seat rather than the vehicle handle catches being thrown through a windscreen
-- as well as opening the door.
CreateThread(function()
    local wasIn = false

    while true do
        Wait(500)

        local inVehicle = IsPedInAnyVehicle(PlayerPedId(), false)
        if wasIn and not inVehicle then
            Compat.resetVehicleState()
            Vehicle.harness = false
            fuelCache.vehicle = 0
        end
        wasIn = inVehicle
    end
end)
