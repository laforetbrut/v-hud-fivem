--[[
    client/minimap.lua

    The minimap is the game's, not the HUD's. Everything here drives it through natives, which
    is why moving it moves the blips and the north marker with it - a NUI copy of the map
    would not.

    Shape is two separate mechanisms and it matters which one is available:

      * SetMinimapClipType picks the engine's own clip. It always works, needs nothing
        streamed, and gives a rounded rectangle or a circle.
      * AddReplaceTexture swaps the radar mask for a streamed one, which is what gives a
        genuinely square map with hard corners.

    The second needs `squaremap` / `circlemap` texture dictionaries to be streaming from
    somewhere. If they are not, the shape falls back to the clip type and the HUD says so once
    in the console rather than silently drawing the wrong shape forever.
]]

Minimap = {}

local applied
local textureState = {}          -- dict name -> true (available) / false (checked, missing)
local warnedMissing = false

-- The native geometry each shape starts from, before the player's offsets are applied. These
-- are screen-fraction units: 1.0 is the full width or height.
local SHAPES = {
    square = {
        clip = 0,
        dict = 'squaremap',
        minimap      = { x = 0.000,  y = -0.047, w = 0.1638, h = 0.183 },
        minimap_mask = { x = 0.000,  y =  0.000, w = 0.1280, h = 0.200 },
        minimap_blur = { x = -0.010, y =  0.025, w = 0.2620, h = 0.300 },
    },
    circle = {
        clip = 1,
        dict = 'circlemap',
        minimap      = { x = -0.010, y = -0.030, w = 0.1800, h = 0.258 },
        minimap_mask = { x =  0.200, y =  0.000, w = 0.0650, h = 0.200 },
        minimap_blur = { x =  0.000, y =  0.015, w = 0.2520, h = 0.338 },
    },
}

--- The horizontal correction an ultrawide screen needs. The minimap natives are laid out for
--- 16:9; without this the map drifts off the left edge as the aspect ratio grows.
local function aspectOffset()
    local width, height = GetActiveScreenResolution()
    if not width or not height or height == 0 then return 0.0 end

    local aspect = width / height
    local base = 1920 / 1080
    if aspect <= base then return 0.0 end

    return ((base - aspect) / 3.6) - 0.008
end

--- Try to stream a mask dictionary. Returns whether it is usable. The answer is cached both
--- ways: a dictionary that is not there will not be there next time either, and requesting it
--- every time the player nudges a slider is a request per nudge.
local function textureReady(dict)
    if textureState[dict] ~= nil then return textureState[dict] end

    RequestStreamedTextureDict(dict, false)

    local deadline = GetGameTimer() + 500
    while not HasStreamedTextureDictLoaded(dict) and GetGameTimer() < deadline do
        Wait(50)
    end

    textureState[dict] = HasStreamedTextureDictLoaded(dict)
    if not textureState[dict] then
        HUD.debug('minimap mask not streaming:', dict)
    end

    return textureState[dict]
end

--- Put the minimap where the settings say. Called on boot, on every settings change, and
--- after a resolution change.
function Minimap.apply(settings)
    if not settings then return end
    applied = settings.minimap

    CreateThread(function()
        local map = applied
        local shape = SHAPES[map.shape] or SHAPES.square
        local offset = aspectOffset()

        SetMinimapClipType(shape.clip)

        if textureReady(shape.dict) then
            AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', shape.dict, 'radarmasksm')
            AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', shape.dict, 'radarmasksm')
        elseif not warnedMissing then
            warnedMissing = true
            HUD.warn('Minimap shape masks are not streaming. The map keeps the game shape; see README > Minimap.')
        end

        -- The player's offsets are a percentage of the screen; the natives want a fraction.
        local dx = (map.x or 0.0) / 100.0
        local dy = -(map.y or 0.0) / 100.0     -- positive Y in the menu means "up"
        local scale = map.scale or 1.0

        for _, component in ipairs({ 'minimap', 'minimap_mask', 'minimap_blur' }) do
            local geometry = shape[component]
            SetMinimapComponentPosition(
                component, 'L', 'B',
                geometry.x + offset + dx,
                geometry.y + dy,
                geometry.w * scale,
                geometry.h * scale
            )
        end

        SetBlipAlpha(GetNorthRadarBlip(), 0)

        -- The bigmap toggle forces the engine to rebuild the minimap with the new mask. Without
        -- it the shape only changes the next time the player opens the pause map, which reads
        -- as "the setting did nothing".
        SetBigmapActive(true, false)
        Wait(50)
        SetBigmapActive(false, false)
        SetMinimapClipType(shape.clip)

        -- Tell the NUI which border to draw, and where. The border is CSS because the native
        -- one cannot be recoloured.
        SendNUIMessage({
            action = 'minimap',
            shape = map.shape,
            borders = map.borders and not map.hide,
            x = map.x,
            y = map.y,
            scale = scale,
        })
    end)
end

--- Whether the radar should be on right now, given the settings and where the player is.
local function shouldShow(settings, inVehicle)
    if not settings then return true end
    if State.manualHide then return false end
    if settings.cinematic and Config.Cinematic.hideMinimap then return false end
    if not settings.show.minimap then return false end
    if settings.minimap.hide then return false end
    if settings.minimap.vehicleOnly and not inVehicle then return false end
    return true
end

-- The radar is off by default: the HUD turns it on once it knows what the player wants, which
-- avoids a frame of the vanilla map in the wrong place on every spawn.
DisplayRadar(false)

CreateThread(function()
    local last

    while true do
        Wait(250)

        local settings = State.settings
        if settings then
            local ped = PlayerPedId()
            local inVehicle = IsPedInAnyVehicle(ped, false)
            local show = shouldShow(settings, inVehicle)

            if show ~= last then
                last = show
                DisplayRadar(show)
            end
        end
    end
end)

-- A resolution or window change moves the safe zone under the map. Re-applying is cheap and
-- the alternative is a minimap that is subtly wrong until the next restart.
CreateThread(function()
    local width, height = GetActiveScreenResolution()

    while true do
        Wait(2000)
        local newWidth, newHeight = GetActiveScreenResolution()
        if newWidth ~= width or newHeight ~= height then
            width, height = newWidth, newHeight
            if State.settings then Minimap.apply(State.settings) end
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- Cinematic bars
-- ---------------------------------------------------------------------------------------

Cinematic = {}

local cinematicOn = false

--- Show or hide the bars. The bars themselves are drawn by the NUI - two divs animate more
--- smoothly than a per-frame DrawRect, and they cost nothing when they are off screen.
function Cinematic.apply(on)
    on = on == true
    if on == cinematicOn then return end
    cinematicOn = on

    SendNUIMessage({
        action = 'cinematic',
        on = on,
        height = Config.Cinematic.barHeight,
        duration = Config.Cinematic.animation,
        hideHud = Config.Cinematic.hideHud,
    })

    if State.settings and State.settings.advanced.notifications then
        Compat.notify(on and L('notify.cinematic_on') or L('notify.cinematic_off'), 'primary')
    end
end

--- Toggle, save, and let the minimap loop pick up the change on its next pass.
function Cinematic.toggle()
    if not State.player then return end
    State.setPath('cinematic', not State.player.cinematic)
end
