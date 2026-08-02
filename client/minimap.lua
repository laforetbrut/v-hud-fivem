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

-- The layout the ENGINE has actually re-read, as a signature. Not just the shape.
--
-- SetMinimapComponentPosition is not the whole story, and this is the trap:
--
--   minimap_mask  updates live. The hole moves the instant the native is called.
--   minimap_blur  updates live.
--   minimap       does NOT. The component that carries the terrain, the blips and the player
--                 arrow only re-reads its rectangle when the minimap is REBUILT - by opening
--                 the pause map, or by toggling the bigmap.
--
-- So moving or resizing the map without a rebuild moves the hole, the blur and the CSS border
-- and leaves the terrain behind: a slab of ground seen from where the map used to be, with the
-- player arrow outside the visible area. That is the "map from somewhere else" bug, and it was
-- introduced by gating the rebuild on the shape alone to kill a flicker.
--
-- The rebuild is therefore owed to ANY geometry change. The flicker it costs is paid once per
-- settled drag, not once per frame, because the whole apply is coalesced above.
local appliedGeometry = nil
local appliedDict = nil
local applyToken = 0

-- True only while the paired SetBigmapActive(true)/SetBigmapActive(false) is in flight, so
-- the watchdog below does not fight the one moment the expanded map is legitimately on.
local rebuilding = false

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

    -- Coalesce. Dragging a slider fires a settings change per frame, and each one used to
    -- start its own thread that resized the map and waited 50ms - which is exactly the
    -- "minimap changes size then goes back" flicker. Only the last change in a burst is
    -- applied.
    applyToken = applyToken + 1
    local token = applyToken

    CreateThread(function()
        Wait(60)
        if token ~= applyToken then return end

        local map = applied
        local shape = SHAPES[map.shape] or SHAPES.square
        local offset = aspectOffset()

        SetMinimapClipType(shape.clip)

        -- The mask texture only depends on the SHAPE, so it is swapped only when the shape
        -- changes. It used to be re-registered on every colour slider nudge.
        if appliedDict ~= shape.dict then
            if textureReady(shape.dict) then
                AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', shape.dict, 'radarmasksm')
                AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', shape.dict, 'radarmasksm')
                appliedDict = shape.dict
            elseif not warnedMissing then
                warnedMissing = true
                HUD.warn(('Minimap mask "%s" is not streaming - the map keeps the game shape while the ' ..
                    'border draws the chosen one, so the two will not line up. The masks ship in ' ..
                    'v-hud/stream; check that folder survived the copy.'):format(shape.dict))
            end
        end

        -- The player's offsets are a percentage of the screen; the natives want a fraction.
        --
        -- THE SIGN ON Y IS NOT A TYPO. Three coordinate systems have to agree here:
        --
        --   the setting   positive y means the map moves UP  (what the slider and the drag say)
        --   the CSS frame `bottom: calc(base + y)`           - larger bottom is higher, so +y
        --   the native    posY grows DOWNWARD even under 'B' alignment, which is why the
        --                 shipped geometry uses y = -0.047 to lift the square map off the
        --                 bottom edge. Moving up therefore means going MORE negative.
        --
        -- Get this wrong and the map slides the opposite way to the mouse while the border
        -- follows the mouse correctly, which is precisely what it looked like.
        local dx = (map.x or 0.0) / 100.0
        local dy = -(map.y or 0.0) / 100.0
        local scale = map.scale or 1.0

        -- Everything the native components are built from. Anything here changing means the
        -- engine has to re-read them, which only a rebuild makes it do.
        local signature = ('%s|%.4f|%.4f|%.4f|%.4f'):format(map.shape or 'square', dx, dy, scale, offset)
        local geometryChanged = appliedGeometry ~= signature

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

        -- The bigmap toggle is what forces the engine to rebuild the minimap, and the rebuild
        -- is the ONLY thing that makes the `minimap` component pick up a new rectangle or a
        -- new mask. It is owed to any geometry change, not only to a change of shape - see the
        -- note on `appliedGeometry` at the top of this file.
        --
        -- One frame is enough for the engine to notice. The 50ms this used to wait was a
        -- visible jump to the full map; Wait(0) is a rebuild the player does not see.
        if geometryChanged then
            appliedGeometry = signature

            -- These two calls are a PAIR and nothing may come between them. An early return
            -- here - a token check, a guard, anything - leaves the expanded map on screen
            -- permanently, because the code that would have closed it never runs. That is
            -- exactly what happened: a second settings change during the wait bailed out of
            -- this block and the player was left staring at the full map.
            --
            -- Coalescing is done BEFORE any of this, at the top of the thread, where bailing
            -- out is free because nothing has been touched yet.
            rebuilding = true
            SetBigmapActive(true, false)
            Wait(0)
            SetBigmapActive(false, false)
            SetMinimapClipType(shape.clip)
            rebuilding = false
        end

        -- Tell the NUI which border to draw, and where. The border is CSS because the native
        -- one cannot be recoloured.
        --
        -- `aspect` is the correction applied to the components just above, as a fraction of
        -- the screen width. The CSS frame has to apply the SAME shift or it leaves the map on
        -- any screen wider than 16:9 - which is the whole ultrawide story in one variable.
        SendNUIMessage({
            action = 'minimap',
            shape = map.shape,
            borders = map.borders and not map.hide,
            x = map.x,
            y = map.y,
            scale = scale,
            aspect = offset,
        })
    end)
end

--- Whether the radar should be on right now, given the settings and where the player is.
local function shouldShow(settings, inVehicle)
    if not settings then return true end
    if State.manualHide then return false end
    -- The game already hides the radar in its own pause menu, but not for another resource's
    -- phone or inventory - and a minimap poking out from under a phone is the same complaint
    -- as a speedometer over it.
    -- The minimap's own answer, not the HUD's: an operator can let a menu hide the gauges and
    -- the speedometer while leaving the map up, which is what you want for anything that only
    -- covers the middle of the screen.
    if Compat.overlayState().minimap then return false end
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
                -- The CSS border is a frame around the native map, so it goes wherever the
                -- map goes. It used to be told only about `minimap.hide`, which meant turning
                -- the minimap off in the Elements tab left an empty rectangle on screen.
                SendNUIMessage({ action = 'radar', on = show })
            end
        end
    end
end)

-- The expanded map, left on, is unrecoverable from the player's side: there is no key that
-- closes it and no setting that mentions it. So it is watched. If it is on while this
-- resource is not in the middle of a shape change, it gets closed.
--
-- This is a net under a bug that has already been fixed once. It costs one native call every
-- two seconds and it means the worst case is a two second flash rather than a broken HUD for
-- the rest of the session.
CreateThread(function()
    local strikes = 0

    while true do
        Wait(2000)

        -- Two consecutive samples before acting. A rebuild started between one sample and the
        -- next is a legitimate bigmap this thread must not close under: with the rebuild now
        -- running on every MOVE rather than only on a shape change, that window is hit far more
        -- often than it used to be.
        if State.ready and not rebuilding and IsBigmapActive() then
            strikes = strikes + 1
            if strikes >= 2 then
                strikes = 0
                HUD.debug('closing an expanded minimap nobody asked for')
                SetBigmapActive(false, false)
            end
        else
            strikes = 0
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
