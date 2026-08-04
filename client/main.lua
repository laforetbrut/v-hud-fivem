--[[
    client/main.lua

    The tick. One loop reads everything the HUD draws and sends it to the NUI, and it sends
    nothing when nothing moved.

    That last part is the whole performance story. A HUD that posts a message every frame
    costs a JSON encode, a browser message and a re-render twenty times a second whether or
    not a single value changed - and standing still is the common case. Each payload is
    compared field by field against the last one sent, and an identical payload is dropped.
]]

local previous = {}
-- Seeded from the clock, not from 0. At 0 the first idle tick computed an age of "however long
-- the game has been running", which is past any immersive delay, so the HUD faded out the
-- instant a player stood still after connecting instead of after their chosen delay.
--
-- Deliberately not nil: line ~203 subtracts from this, and nil there raises inside the tick
-- thread, which would take the whole HUD down.
local lastActivity = GetGameTimer()
local faded = false

--[[
    Whether `payload` differs from the last one sent.

    This has to RECURSE, and the reason is worth stating because the previous version looked
    perfectly reasonable and did nothing at all.

    It walked one level and compared anything deeper with `~=`. But `vehicle.doors`,
    `vehicle.lights` and `vehicle.thresholds` are fresh tables built on every pass, so at
    depth two the comparison was between two distinct references - never equal. The answer
    was therefore "changed" on every single tick anyone spent in a vehicle, and the whole
    suppression this function exists for was dead: 600 messages sent out of 600 identical
    ticks in a parked car, against 1 out of 600 on foot.

    The payload is three levels deep at most and every leaf is a scalar, so the recursion is
    bounded. It measures at roughly 9 microseconds against 2.4 for the shallow version - far
    below the json.encode and NUI round trip it now avoids.

    A note for anyone tempted to store `previous` differently: `previous = payload` keeps a
    reference, and that is safe only because every tick builds a completely new table. If a
    sub-table is ever cached and mutated in place, this comparison will stop seeing changes.
]]
local function same(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end

    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end

    return true
end

local function changed(payload)
    return not same(payload, previous)
end

-- ---------------------------------------------------------------------------------------
-- Status readings
-- ---------------------------------------------------------------------------------------

--- Health as 0-100 of the ped's own range. GTA gives a ped 100 points of "dead" underneath
--- its health, so the raw value never reaches zero and a naive percentage never empties.
local function health(ped)
    local maximum = GetEntityMaxHealth(ped)
    local current = GetEntityHealth(ped)
    local span = maximum - 100

    if span <= 0 then return 0 end
    return HUD.clamp(((current - 100) / span) * 100, 0, 100, 0)
end

--- Oxygen underwater, and stamina on land. Two different natives behind one gauge, because
--- they are never both relevant at once.
local function breath(ped, playerId)
    if IsEntityInWater(ped) and IsPedSwimmingUnderWater(ped) then
        return HUD.clamp(GetPlayerUnderwaterTimeRemaining(playerId) * 10, 0, 100, 100), true
    end
    return 100, false
end

local function stamina(playerId)
    return HUD.clamp(100 - GetPlayerSprintStaminaRemaining(playerId), 0, 100, 100)
end

--- Whether the player is holding something that counts as a weapon. Config decides what a
--- weapon is, so a server that considers a fire extinguisher threatening can say so.
local function armed(ped)
    local weapon = GetSelectedPedWeapon(ped)
    if weapon == `WEAPON_UNARMED` then return false end
    return not Config.Stress.unarmedLike[weapon]
end

--- Values from Config.Status entries the operator added. Native and metadata sources are
--- handled here so that adding a gauge really is a config-only change.
local function customStatuses()
    local out = nil

    for _, status in ipairs(Config.Status) do
        if status.source == 'metadata' and status.field then
            local known = status.field == 'hunger' or status.field == 'thirst' or status.field == 'stress'
            if not known then
                out = out or {}
                out[status.key] = math.floor(Needs.metadata(status.field) + 0.5)
            end
        end
    end

    return out
end

-- ---------------------------------------------------------------------------------------
-- Immersive mode
-- ---------------------------------------------------------------------------------------

--- Anything that should bring a faded HUD back. Deliberately generous: a player who cannot
--- see their health because they are standing still is a player who thinks the HUD broke.
local function isActive(ped, payload, before)
    if payload.inVehicle then return true end
    if payload.dead then return true end
    if payload.armed then return true end
    if payload.talking then return true end
    if IsPedRunning(ped) or IsPedSprinting(ped) then return true end
    if IsPlayerFreeAiming(PlayerId()) then return true end

    for _, key in ipairs({ 'health', 'armor', 'hunger', 'thirst', 'stress', 'oxygen' }) do
        if before[key] ~= nil and before[key] ~= payload[key] then return true end
    end

    return false
end

-- ---------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local settings = State.settings

        if not State.ready or not settings then
            Wait(500)
        else
            -- The player's chosen refresh rate. Validated server-side against
            -- Config.Tick.rates, so the lookup below cannot come back nil; the `or` is the
            -- belt to that braces for a config edited while the server was running.
            Wait(Config.Tick.rates[settings.advanced.refresh]
                or Config.Tick.rates[Config.Tick.defaultRate]
                or 16)

            local ped = PlayerPedId()
            local playerId = PlayerId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local inVehicle = vehicle ~= 0

            local oxygen, underwater = breath(ped, playerId)
            local voice = settings.show.voice and Compat.voice() or nil
            local playerData = Compat.playerData()

            -- ONE place decides whether the HUD is drawn, because the NUI writes the answer
            -- to one attribute per tick: a second writer (the cinematic handler used to be
            -- one) gets overruled twenty times a second and reads as "the setting flickers".
            --
            -- Compat.overlayOpen() covers the pause menu, the map screen, a loading screen,
            -- another resource's NUI focus, and any resource that publishes an "am I open"
            -- export - the phone above all. A speedometer over somebody's phone is the HUD
            -- being in the way.
            local visible = not Compat.overlayOpen()
                and not State.manualHide
                and not (settings.cinematic and Config.Cinematic.hideHud)

            local payload = {
                action = 'tick',
                show = visible,
                dead = IsEntityDead(ped)
                    or (playerData.metadata and (playerData.metadata['isdead'] or playerData.metadata['inlaststand']))
                    or false,

                health = math.floor(health(ped) + 0.5),
                armor = math.floor(GetPedArmour(ped) + 0.5),
                hunger = math.floor(Needs.hunger + 0.5),
                thirst = math.floor(Needs.thirst + 0.5),
                stress = math.floor(Needs.stress + 0.5),
                oxygen = math.floor(oxygen + 0.5),
                underwater = underwater,
                stamina = math.floor(stamina(playerId) + 0.5),
                sprinting = IsPedRunning(ped) or IsPedSprinting(ped),

                armed = settings.show.armed and armed(ped) or false,
                parachute = GetPedParachuteState(ped),
                inVehicle = inVehicle,
                custom = customStatuses(),
            }

            if voice then
                payload.voiceRange = voice.range
                payload.talking = voice.talking
                payload.radio = voice.radio
                payload.radioActive = voice.radioActive
            end

            if inVehicle then
                -- Read whenever there is a vehicle, not only when the cluster is on screen:
                -- the belt and door chimes are a safety warning, and hiding the speedometer
                -- is a choice about what to LOOK at, not a request to drive without them.
                local data = Vehicle.read(vehicle, settings)
                Vehicle.warn(data)

                if settings.show.speedometer then payload.vehicle = data end
            end

            -- Immersive mode. The timer is reset by anything that counts as activity, and the
            -- fade itself is a CSS class the NUI toggles rather than a per-frame opacity.
            if settings.immersive then
                if isActive(ped, payload, previous) then
                    lastActivity = GetGameTimer()
                    if faded then
                        faded = false
                        payload.faded = false
                    end
                elseif not faded and (GetGameTimer() - lastActivity) > (settings.immersiveDelay * 1000) then
                    faded = true
                    payload.faded = true
                end
                payload.faded = faded
            elseif faded then
                faded = false
                payload.faded = false
            end

            if changed(payload) then
                previous = payload
                SendNUIMessage(payload)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------------------------

-- There is no money element on this HUD, on purpose. A cash and bank readout parked in the
-- corner of the screen all session is the first thing every player turns off, so it is not
-- drawn at all - not as a permanent row, and not as a banner every time a wallet moves.
--
-- What is left is the part somebody actually asks for: `/cash` and `/bank` answer, once, as
-- a toast that appears and goes away like any other message.

--- Group thousands the way the operator configured, with the currency symbol on their side.
local function formatMoney(amount)
    local text = tostring(math.floor(math.abs(tonumber(amount) or 0)))
    local separator = Config.Money.thousands or ' '

    -- Grouping is done on the REVERSED string, because digits group from the right and Lua
    -- patterns only scan left to right. `123456` reversed is `654321`, which chunks cleanly
    -- into `654 321` and reverses back to `123 456`.
    local grouped = text:reverse():gsub('(%d%d%d)', '%1' .. separator):reverse()

    -- A number whose digit count is an exact multiple of three picks up a leading separator.
    -- The separator is escaped before it is used as a pattern: a '.' would otherwise match
    -- the first character whatever it is.
    grouped = grouped:gsub('^' .. separator:gsub('%W', '%%%0'), '')

    if Config.Money.symbolPosition == 'suffix' then
        return grouped .. (Config.Money.symbol or '')
    end
    return (Config.Money.symbol or '') .. grouped
end

local function accountWatched(account)
    for _, name in ipairs(Config.Money.accounts) do
        if name == account then return true end
    end
    return false
end

local function showAccount(account, amount)
    if not accountWatched(account) then return end

    SendNUIMessage({
        action = 'showAccount',
        text = ('%s  %s'):format(L('money.' .. account), formatMoney(amount)),
        duration = Config.Money.balanceDuration,
    })
end

RegisterNetEvent('vhud:client:ShowAccount', function(account, amount)
    showAccount(account, amount)
end)

if Config.Compat.qbHudEvents then
    -- qb-hud's name for the same thing. The passive `hud:client:OnMoneyChange` is deliberately
    -- NOT answered: it is what drew a banner on every transaction.
    RegisterNetEvent('hud:client:ShowAccounts', function(account, amount)
        showAccount(account, amount)
    end)
end

-- ---------------------------------------------------------------------------------------
-- The qb-hud client events that have nowhere else to live
-- ---------------------------------------------------------------------------------------

if Config.Compat.qbHudEvents then
    -- qb-hud toggled an altitude readout from outside. Kept so a resource that fires it does
    -- not silently do nothing.
    RegisterNetEvent('hud:client:ToggleAirHud', function()
        if not State.player then return end
        State.setPath('speedometer.altitude', not State.player.speedometer.altitude)
    end)

    RegisterNetEvent('hud:client:ToggleShowSeatbelt', function()
        if not State.player then return end
        State.setPath('speedometer.belt', not State.player.speedometer.belt)
    end)

    -- Reloading the map was a qb-hud event other resources fired after changing the radar.
    RegisterNetEvent('hud:client:LoadMap', function()
        if State.settings then Minimap.apply(State.settings) end
    end)
end

RegisterNetEvent('vhud:client:LoadMap', function()
    if State.settings then Minimap.apply(State.settings) end
end)

-- Dev mode: qb-adminmenu fires this, and the marker is one more thing a player can turn off.
local devMode = false
RegisterNetEvent('qb-admin:client:ToggleDevmode', function()
    devMode = not devMode
    SendNUIMessage({ action = 'dev', on = devMode and (State.settings and State.settings.show.dev) })
end)
