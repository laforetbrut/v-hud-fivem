--[[
    client/odometer.lua

    How far a vehicle has been driven.

    GTA does not keep this. There is no native for "how far has this car been", and the
    engine's own dashboard mileage is not exposed. So it is measured: while the player is the
    driver, the distance between one sample and the next is added to a running total for that
    number plate, and the total is handed to the server to store.

    Two things this deliberately does NOT do:

      * It does not count distance the player did not drive. Only the driver's seat
        accumulates, so a passenger does not add to somebody else's odometer, and a car being
        towed or teleported does not either - a jump larger than the sampling interval could
        physically produce is discarded rather than added.
      * It does not fight another resource. If a state bag from a mileage script answers, that
        number is used and nothing is tracked. One mileage is better than two that disagree.
]]

Odometer = {}

local SAMPLE_MS = 1000

-- Plate -> metres. The client's working copy; the server owns the stored value and sends it
-- back when a plate is first seen.
local totals = {}
local pending = {}       -- metres not yet saved, per plate
local lastPosition = nil
local lastPlate = nil

--- A plate string, trimmed. GetVehicleNumberPlateText pads to eight characters, and a padded
--- plate and a trimmed one are different database rows.
local function plateOf(vehicle)
    if not vehicle or vehicle == 0 then return nil end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return nil end

    plate = plate:gsub('^%s*(.-)%s*$', '%1')
    return plate ~= '' and plate or nil
end

--- A mileage published by another resource, in metres, or nil.
local function fromProvider(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local state = Entity(vehicle).state
    if not state then return nil end

    for _, bag in ipairs(Config.Odometer.providers or {}) do
        local value = state[bag]
        if type(value) == 'number' and value >= 0 then return value end
    end

    return nil
end

--- Metres for `vehicle`, from a provider or from this resource's own total. nil when there is
--- nothing to show, which is what hides the readout rather than printing a zero.
function Odometer.metres(vehicle)
    if not Config.Odometer.enabled then return nil end

    local provided = fromProvider(vehicle)
    if provided then return provided end

    if not Config.Odometer.track then return nil end

    local plate = plateOf(vehicle)
    if not plate then return nil end

    return (totals[plate] or 0) + (pending[plate] or 0)
end

--[[
    Metres formatted for the speedometer, in the unit the operator chose.

    Called on every tick, so the two easy allocations are worth removing:

    The format string was rebuilt from pieces on every call ('%.' .. decimals .. 'f'), which
    is two string concatenations a frame to produce the same handful of characters. The
    operator's `decimals` cannot change at runtime, so it is built once.

    THE RETURNED TABLE IS DELIBERATELY STILL ALLOCATED FRESH, and must stay that way.

    Reusing one would look like an easy second saving and would silently break the odometer.
    The tick dedupe in client/main.lua keeps the last payload BY REFERENCE, so a sub-table
    mutated in place would be compared against itself: `same()` would report no change and
    the mileage would never reach the screen again. The allocation is the price of that
    comparison working, and it is a cheap one.
]]
local formatCache = nil

function Odometer.display(vehicle, playerUnits)
    local metres = Odometer.metres(vehicle)
    if not metres then return nil end

    local unit = Config.Odometer.unit
    if unit == 'units' then unit = playerUnits == 'mph' and 'mi' or 'km' end

    local value = unit == 'mi' and (metres / 1609.344) or (metres / 1000.0)

    if not formatCache then
        formatCache = '%.' .. (Config.Odometer.decimals or 0) .. 'f'
    end

    return {
        value = tonumber(string.format(formatCache, value)),
        unit = unit == 'mi' and 'MI' or 'KM',
    }
end

RegisterNetEvent('vhud:client:Odometer', function(plate, metres)
    if type(plate) ~= 'string' then return end
    totals[plate] = tonumber(metres) or 0
    pending[plate] = nil
end)

--- Hand the unsaved metres to the server and start counting again from zero.
local function flush(plate)
    local metres = pending[plate]
    if not metres or metres < 1 then return end

    pending[plate] = nil
    totals[plate] = (totals[plate] or 0) + metres
    TriggerServerEvent('vhud:server:Odometer', plate, math.floor(metres))
end

CreateThread(function()
    while true do
        Wait(SAMPLE_MS)

        if not Config.Odometer.enabled or not Config.Odometer.track or not State.ready then
            lastPosition = nil
        else
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped)
                and plateOf(vehicle) or nil

            if not plate then
                -- Out of the driver's seat: bank whatever was counted and stop.
                if lastPlate then flush(lastPlate) end
                lastPlate, lastPosition = nil, nil
            else
                local position = GetEntityCoords(vehicle)

                if plate ~= lastPlate then
                    -- A different car. Bank the old one and start clean rather than counting
                    -- the walk between them.
                    if lastPlate then flush(lastPlate) end
                    lastPlate = plate
                    lastPosition = position

                    if totals[plate] == nil then
                        TriggerServerEvent('vhud:server:OdometerRequest', plate)
                    end
                elseif lastPosition then
                    local metres = #(position - lastPosition)

                    -- A sample cannot legitimately be more than a very fast car covers in one
                    -- interval. Anything larger is a teleport, a tow, a respawn or the vehicle
                    -- being streamed back in somewhere else - none of which anybody drove.
                    local ceiling = 200.0 * (SAMPLE_MS / 1000.0)
                    if metres > 0.5 and metres < ceiling then
                        pending[plate] = (pending[plate] or 0) + metres
                        if (pending[plate] or 0) >= Config.Odometer.saveEvery then
                            flush(plate)
                        end
                    end

                    lastPosition = position
                end
            end
        end
    end
end)

-- Getting out is the moment the number matters, so it is banked immediately rather than at
-- the next kilometre.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if lastPlate then flush(lastPlate) end
end)

--- The odometer for a vehicle, for another resource.
exports('GetOdometer', function(vehicle)
    return Odometer.metres(vehicle)
end)
