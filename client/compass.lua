--[[
    client/compass.lua

    The compass and the street names. Both run on their own loops, slower than the main HUD
    tick, because a heading recomputed twenty times a second reads as jitter rather than as
    smoothness, and a street name only changes when you cross a junction.

    Two headings exist and the difference is worth knowing: the camera's, which is what a
    player means by "which way am I looking", and the ped's, which is where the character is
    actually facing. The `follow` setting picks between them.
]]

Compass = {}

local CARDINALS = {
    { max = 22.5,  key = 'dir.n' },
    { max = 67.5,  key = 'dir.ne' },
    { max = 112.5, key = 'dir.e' },
    { max = 157.5, key = 'dir.se' },
    { max = 202.5, key = 'dir.s' },
    { max = 247.5, key = 'dir.sw' },
    { max = 292.5, key = 'dir.w' },
    { max = 337.5, key = 'dir.nw' },
}

--- The cardinal for a bearing in degrees. The last band wraps back to north, which is why
--- the table stops at 337.5 rather than at 360.
function Compass.cardinal(bearing)
    for _, band in ipairs(CARDINALS) do
        if bearing < band.max then return L(band.key) end
    end
    return L('dir.n')
end

--- Compass bearing, 0-359, where 0 is north. GTA headings run counter-clockwise from north,
--- so they are mirrored here rather than in the NUI: every consumer wants the compass one.
local function bearing(follow)
    local raw

    if follow then
        raw = GetGameplayCamRot(0).z
    else
        raw = GetEntityHeading(PlayerPedId())
    end

    local degrees = (360.0 - (raw % 360.0)) % 360.0
    return degrees
end

CreateThread(function()
    local lastSent = -1
    local lastCardinal = nil
    local wasVisible = nil

    while true do
        local settings = State.settings

        -- The heading is computed whenever ANYTHING wants it, not only when the compass is on
        -- screen: the street banner carries the same cardinal, and it has to keep updating
        -- while the street name does not change.
        local wantsCompass = settings and settings.show.compass
        local wantsHeading = settings and settings.show.streets and settings.streets.direction

        if not settings or (not wantsCompass and not wantsHeading) then
            Wait(500)
        else
            local inVehicle = IsPedInAnyVehicle(PlayerPedId(), false)
            local visible = wantsCompass and not (settings.compass.vehicleOnly and not inVehicle)

            if visible ~= wasVisible then
                wasVisible = visible
                SendNUIMessage({ action = 'compass', show = visible })
                -- Becoming visible has to invalidate the heading cache. The message above
                -- carries no degrees, so the page resets to 0, and if the player has not
                -- turned since it was last sent the "only send when it moved" test below never
                -- fires again - a compass frozen at north until you look somewhere else.
                if visible then lastSent = -1 end
            end

            local degrees = bearing(settings.compass.follow)
            local rounded = math.floor(degrees + 0.5) % 360

            -- Only send when the value actually moved. Standing still is the common case and
            -- it should cost one comparison, not a NUI message.
            if rounded ~= lastSent then
                lastSent = rounded
                local cardinal = Compass.cardinal(degrees)

                if visible then
                    SendNUIMessage({
                        action = 'compass',
                        show = true,
                        degrees = rounded,
                        cardinal = cardinal,
                    })
                end

                if wantsHeading and cardinal ~= lastCardinal then
                    lastCardinal = cardinal
                    SendNUIMessage({ action = 'heading', cardinal = cardinal })
                end
            end

            Wait(Config.Tick.compass)
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Street names
-- ---------------------------------------------------------------------------------------

--- A street hash turned into text, or an empty string. GetStreetNameFromHashKey returns the
--- raw name for a street it knows and nothing for one it does not, and "NULL" for a couple of
--- unnamed alleys - all three have to come out as empty.
local function streetName(hash)
    if not hash or hash == 0 then return '' end

    local name = GetStreetNameFromHashKey(hash)
    if not name or name == '' or name == 'NULL' then return '' end
    return name
end

CreateThread(function()
    local last = { street = '', crossing = '', zone = '' }

    while true do
        local settings = State.settings

        if not settings or not settings.show.streets then
            Wait(600)
        else
            local ped = PlayerPedId()
            local inVehicle = IsPedInAnyVehicle(ped, false)

            if settings.streets.vehicleOnly and not inVehicle then
                if last.street ~= nil then
                    last = { street = nil }
                    SendNUIMessage({ action = 'streets', show = false })
                end
                Wait(500)
            else
                local coords = GetEntityCoords(ped)
                local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)

                local street = streetName(streetHash)
                local crossing = settings.streets.crossing and streetName(crossingHash) or ''
                local zone = ''

                if settings.streets.zone then
                    local zoneLabel = GetNameOfZone(coords.x, coords.y, coords.z)
                    zone = GetLabelText(zoneLabel)
                    if zone == 'NULL' then zone = '' end
                end

                if street ~= last.street or crossing ~= last.crossing or zone ~= last.zone then
                    last = { street = street, crossing = crossing, zone = zone }

                    SendNUIMessage({
                        action = 'streets',
                        show = street ~= '' or zone ~= '',
                        street = street,
                        crossing = crossing,
                        zone = zone,
                        uppercase = settings.streets.uppercase,
                    })
                end

                Wait(Config.Tick.streets)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------

--- The street and district the player is standing in. Published because half a dozen
--- resources want it and every one of them writes the same twelve lines to get it.
exports('GetLocation', function()
    local coords = GetEntityCoords(PlayerPedId())
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local zoneLabel = GetNameOfZone(coords.x, coords.y, coords.z)
    local zone = GetLabelText(zoneLabel)

    return {
        street = streetName(streetHash),
        crossing = streetName(crossingHash),
        zone = zone ~= 'NULL' and zone or '',
        heading = math.floor(bearing(true) + 0.5) % 360,
        cardinal = Compass.cardinal(bearing(true)),
    }
end)
