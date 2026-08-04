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

--- Which doors are not shut. Index 4 is the bonnet and 5 is the boot, so "a door is open" and
--- "the bonnet is up" are reported separately - one is a warning you drive away from, the
--- other is usually the mechanic working on you.
---
--- The angle ratio is used rather than IsVehicleDoorFullyOpen, because a door that is ajar is
--- exactly the case worth warning about and "fully open" misses it.
local function doors(vehicle)
    local anyDoor, bonnet, boot = false, false, false

    for index = 0, 5 do
        local ok, ratio = pcall(GetVehicleDoorAngleRatio, vehicle, index)
        if ok and type(ratio) == 'number' and ratio > 0.01 then
            if index == 4 then bonnet = true
            elseif index == 5 then boot = true
            else anyDoor = true end
        end
    end

    return { door = anyDoor, bonnet = bonnet, boot = boot }
end

--- Is this native out-parameter set?
---
--- Cfx hands BOOL out-parameters back as `true`/`false` on some builds and as `1`/`0` on
--- others, so neither `== true` nor `== 1` is safe on its own. Comparing against 1 was why the
--- headlight tell-tales never lit: the value was `true`, and `true == 1` is false in Lua.
local function isSet(value)
    if type(value) == 'boolean' then return value end
    if type(value) == 'number' then return value ~= 0 end
    return false
end

--- Indicator and light state. Both natives return through out-parameters, and both are
--- wrapped because a vehicle handle can die between the check and the call.
local function lights(vehicle)
    -- GET_VEHICLE_LIGHTS_STATE is `BOOL fn(Vehicle, BOOL* lightsOn, BOOL* highbeamsOn)`, so
    -- Lua receives THREE values: the return, then the two out-parameters. pcall puts its own
    -- success flag in front of all of them, making four.
    --
    -- Destructuring only three dropped the high-beam value on the floor and shifted the other
    -- two down a slot - `lightsOn` was really the return value, `highBeams` was really
    -- lightsOn. Every headlight lamp was reading the wrong variable.
    local ok, _, lightsOn, highBeams = pcall(GetVehicleLightsState, vehicle)
    local left, right = false, false

    local okIndicators, indicatorState = pcall(GetVehicleIndicatorLights, vehicle)
    if okIndicators and type(indicatorState) == 'number' then
        -- 0 none, 1 left, 2 right, 3 both (hazards).
        left = indicatorState == 1 or indicatorState == 3
        right = indicatorState == 2 or indicatorState == 3
    end

    -- Main beam implies the headlights are on, whatever the out-parameter says: some vehicles
    -- report lightsOn false while the high beams are lit, and a dark headlight lamp next to a
    -- lit main-beam lamp reads as a broken HUD.
    local high = ok and isSet(highBeams)

    return {
        on = (ok and isSet(lightsOn)) or high,
        high = high,
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
        doors = doors(vehicle),
        handbrake = isSet(GetVehicleHandbrake(vehicle)),
        -- Whether the engine is RUNNING, which is a different question from how healthy it is.
        -- The tell-tale needs both: a switched-off engine in perfect condition must not sit
        -- there lit green.
        engineOn = isSet(GetIsVehicleEngineRunning(vehicle)),
        -- Per-part wear from whichever mechanic script is installed, or nil. Drives the
        -- brake, coolant, driveline and battery tell-tales.
        parts = Compat.vehicleParts(vehicle),
        partWarning = Config.Compat.partWarning or 50,
        -- The thresholds the lamps light at, so the NUI never has to invent one.
        thresholds = {
            lowFuel = Config.Cluster.lowFuel or 25,
            lowFuelCritical = Config.Cluster.lowFuelCritical or 8,
            engineFault = Config.Cluster.engineFault or 25,
        },
        -- Total distance this vehicle has covered. nil when nothing is tracking it, which
        -- hides the readout rather than printing a zero on every car in the city.
        odometer = Odometer and Odometer.display(vehicle, settings.units) or nil,
        aircraft = isAircraft,
        altitude = isAircraft and math.floor(GetEntityCoords(ped).z * 0.5) or nil,
        -- A bicycle has no engine, no fuel and no gears; the NUI hides those readouts rather
        -- than drawing three zeros.
        bicycle = IsThisModelABicycle(GetEntityModel(vehicle)),
        driver = GetPedInVehicleSeat(vehicle, -1) == ped,
    }
end

-- ---------------------------------------------------------------------------------------
-- Driving warnings
-- ---------------------------------------------------------------------------------------

-- Two chimes, driven off the same data the speedometer already reads, so the tell-tale on the
-- cluster and the sound in the player's ears can never disagree.
--
-- The state is per-condition rather than a single timer: an open door and an unfastened belt
-- are separate faults, and fixing one must not silence the other.
-- `since` and `last` are nil when unset, NOT zero. Zero is a perfectly good game timer value,
-- so using it as the sentinel silently threw away the first tick after a resource restart.
local warnings = {
    seatbelt = { since = nil, last = nil },
    door = { since = nil, last = nil },
}

local function chime(key, active, now)
    local rules = Config.Alerts and Config.Alerts[key]
    local track = warnings[key]

    if not rules or not rules.enabled or not active then
        -- Both are cleared, not just the timer. Leaving `last` set would make `interval = 0`
        -- - documented as "once per occurrence" - mean "once, ever".
        track.since, track.last = nil, nil
        return
    end

    -- The fault has to hold for the grace period before anything sounds. Without it, every
    -- door tap at a junction is a beep.
    if not track.since then
        track.since = now
        return
    end

    if (now - track.since) < (Config.Alerts.grace or 0) then return end

    local interval = rules.interval or 0
    if track.last and (interval <= 0 or (now - track.last) < interval) then return end

    track.last = now
    -- Routed through Compat so a player who turned HUD sounds off gets none of this.
    Compat.playFrontendSound(rules.sound, rules.set)
end

--- Sound the belt and door warnings for `data`, the table `Vehicle.read` just returned.
--- Reads only; every decision is already in that table.
function Vehicle.warn(data)
    if not Config.Alerts or not data or data.bicycle then
        -- BOTH fields, which is what resetWarnings does. Clearing only `since` left `last` set,
        -- and an interval of 0 - documented as "once per occurrence" - then meant "once, ever"
        -- for anyone who had been a passenger or on a bicycle since the last chime.
        Vehicle.resetWarnings()
        return
    end

    local now = GetGameTimer()
    local fast = data.speed > (Config.Alerts.speed or 40)
    local doorState = data.doors or {}
    local driving = data.driver == true

    local doorOpen = doorState.door == true
    if Config.Alerts.includeBootAndBonnet then
        doorOpen = doorOpen or doorState.bonnet == true or doorState.boot == true
    end

    -- The belt warning is actionable from a passenger seat: they can buckle, and they are
    -- thrown through the windscreen if they do not. A switch rather than a decision, because
    -- a chime nobody can silence is the fastest way to make players mute the HUD.
    local beltSeats = driving
        or (Config.Alerts.seatbelt and Config.Alerts.seatbelt.passengers) == true

    -- The door warning stays the driver's. A passenger cannot pull over.
    chime('seatbelt', beltSeats and fast and data.seatbelt ~= true, now)
    chime('door', driving and fast and doorOpen, now)
end

--- Forget both warnings. Called on leaving a vehicle, so getting back in starts the grace
--- period again rather than chiming on the first frame.
function Vehicle.resetWarnings()
    warnings.seatbelt.since, warnings.seatbelt.last = nil, nil
    warnings.door.since, warnings.door.last = nil, nil
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
            Vehicle.resetWarnings()
            Vehicle.harness = false
            fuelCache.vehicle = 0
        end
        wasIn = inVehicle
    end
end)
