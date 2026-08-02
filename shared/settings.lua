--[[
    shared/settings.lua

    One implementation of "what is a valid settings table", used by both sides.

    The client calls it so the menu can never put a nonsense value on screen. The server calls
    it on the payload a client sends before anything is written to disk, because a NUI page is
    a browser and a browser is not trustworthy. Having one implementation is the point: two
    validators drift, and the day they drift is the day a client writes a CSS expression into
    a colour field.

    Order of operations on save, and it matters:
        1. merge into the defaults      - drops keys the schema does not know
        2. coerce and clamp             - numbers, enums, colours
        3. apply policy                 - locked paths forced back to the default
]]

Settings = {}

-- Extra status gauges the operator added to Config.Status need a `show` switch and a colour,
-- or the menu would offer a gauge with nothing behind it. Filled in once, at load.
local schema
local function buildSchema()
    if schema then return schema end

    schema = HUD.deepCopy(Config.Defaults)

    for _, status in ipairs(Config.Status or {}) do
        if schema.show[status.key] == nil then
            schema.show[status.key] = true
        end
        if schema.colours[status.key] == nil then
            schema.colours[status.key] = schema.colours.accent
        end
    end

    return schema
end

--- A fresh copy of the server defaults. Every caller gets its own table.
function Settings.default()
    return HUD.deepCopy(buildSchema())
end

-- ---------------------------------------------------------------------------------------
-- Dotted paths
-- ---------------------------------------------------------------------------------------

--- Read `a.b.c` out of `tbl`. nil for any missing link, never an error.
function Settings.getPath(tbl, path)
    local node = tbl
    for part in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    return node
end

--- Write `value` at `a.b.c` in `tbl`, but only where the path already exists. A path the
--- schema does not know is silently ignored rather than created - that is what stops a
--- locked-path typo in config.lua from inventing a setting.
function Settings.setPath(tbl, path, value)
    local parts = {}
    for part in path:gmatch('[^%.]+') do parts[#parts + 1] = part end
    if #parts == 0 then return false end

    local node = tbl
    for i = 1, #parts - 1 do
        node = node[parts[i]]
        if type(node) ~= 'table' then return false end
    end

    local leaf = parts[#parts]
    if node[leaf] == nil then return false end
    node[leaf] = value
    return true
end

-- The two things a player keeps whatever the server says.
--
-- This is a promise the resource makes, so it is enforced here rather than left to whoever
-- edits config.lua: `positions` is how a player arranges their own screen, and the minimap
-- shape is the single most personal preference in the whole HUD. A config that lists either
-- is warned about and ignored.
local NEVER_LOCKABLE = { 'positions', 'minimap.shape' }

local function isProtected(path)
    for _, keep in ipairs(NEVER_LOCKABLE) do
        if path == keep or path:sub(1, #keep + 1) == keep .. '.' then return true end
    end
    return false
end

--- Whether the server has locked `path`. Exact match, or any ancestor: locking `colours`
--- locks every colour under it.
function Settings.isLocked(path)
    if isProtected(path) then return false end

    for _, locked in ipairs(Settings.lockedPaths()) do
        if locked == path then return true end
        if path:sub(1, #locked + 1) == locked .. '.' then return true end
    end
    return false
end

-- Warned-about paths, so a config mistake is reported once rather than on every menu row.
local warnedProtected = {}

--- Every locked path, as a flat array, for the NUI to draw padlocks with.
---
--- Deliberately NOT memoised. The list is a handful of strings and it is derived from
--- Config.Policy, which a server owner edits and reloads; a cache here means the first call
--- of the session decides the rules for the rest of it.
function Settings.lockedPaths()
    local policy = Config.Policy
    local out = {}
    local seen = {}

    local function add(path)
        if seen[path] then return end

        if isProtected(path) then
            if not warnedProtected[path] then
                warnedProtected[path] = true
                HUD.warn(('Config.Policy tried to lock "%s". Players always keep their layout ' ..
                    'and their minimap shape, so it has been ignored.'):format(path))
            end
            return
        end

        seen[path] = true
        out[#out + 1] = path
    end

    for _, path in ipairs(policy.locked or {}) do add(path) end

    -- A forced theme or cluster locks its own picker.
    if policy.forcedTheme then add('theme') end
    if policy.forcedSpeedometer then add('speedometer.style') end

    -- Every forced style key and colour.
    for key in pairs(policy.forcedStyle or {}) do add('style.' .. key) end
    for key in pairs(policy.forcedColours or {}) do add('colours.' .. key) end

    -- An element that is forced on or removed is not the player's to switch.
    for key, mode in pairs(policy.elements or {}) do
        if mode == 'forced' or mode == 'off' then add('show.' .. key) end
    end

    -- A list with one entry left is not a choice.
    if #(policy.themes or {}) <= 1 then add('theme') end
    if #(policy.speedometers or {}) <= 1 then add('speedometer.style') end
    if #(policy.gaugeShapes or {}) <= 1 then add('style.gauge') end
    if #(policy.surfaces or {}) <= 1 then add('style.surface') end
    if #(policy.compassStyles or {}) <= 1 then add('compass.style') end

    return out
end

--- How the server treats an element: 'player', 'forced' or 'off'.
function Settings.elementMode(key)
    local mode = (Config.Policy.elements or {})[key]
    if mode == 'forced' or mode == 'off' then return mode end
    return 'player'
end

--- The elements this server removed outright, for the NUI to leave out of the menu.
function Settings.removedElements()
    local out = {}
    for key, mode in pairs(Config.Policy.elements or {}) do
        if mode == 'off' then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------------------------------
-- Coercion
-- ---------------------------------------------------------------------------------------

local function bound(name)
    return (Config.Policy.bounds or {})[name] or { min = 0, max = 1 }
end

local function clampTo(value, name, fallback)
    local limits = bound(name)
    return HUD.clamp(value, limits.min, limits.max, fallback)
end

local function enum(value, allowed, fallback)
    return HUD.oneOf(value, allowed) and value or fallback
end

-- Twelve shapes. This list is the contract with html/js/status.js: a value that is legal here
-- and unknown there renders nothing, so the two must be changed together.
local GAUGE_SHAPES = {
    'square', 'rounded', 'pill', 'circle', 'ring', 'radial',
    'dot', 'bar', 'segment', 'diamond', 'hex', 'icon',
}
local SURFACES = { 'glass', 'tint', 'solid', 'none' }
local DIRECTIONS = { 'row', 'column' }
local UNITS = { 'kmh', 'mph' }
local COMPASS_STYLES = { 'bar', 'tape', 'dial', 'text' }

-- Square or round, always. This is one of the two promises to the player, so the list is a
-- constant here and there is no Config.Policy entry that can shorten it.
local MAP_SHAPES = { 'square', 'circle' }

--- The values the server offers for a setting: the intersection of what this resource can
--- render and what Config.Policy allows. An operator list that names nothing valid falls back
--- to the full list rather than leaving the player with no options at all.
local function offered(policyKey, everything)
    local allowed = Config.Policy[policyKey]
    if type(allowed) ~= 'table' or #allowed == 0 then return everything end

    local out = {}
    for _, value in ipairs(allowed) do
        if HUD.oneOf(value, everything) then out[#out + 1] = value end
    end

    return #out > 0 and out or everything
end

--- Every choice list the menu renders, so the NUI never offers something the server refuses.
function Settings.choices()
    return {
        gaugeShapes = offered('gaugeShapes', GAUGE_SHAPES),
        surfaces = offered('surfaces', SURFACES),
        compassStyles = offered('compassStyles', COMPASS_STYLES),
        mapShapes = MAP_SHAPES,
        directions = DIRECTIONS,
        units = UNITS,
        removed = Settings.removedElements(),
    }
end
local ANCHORS = { 'left', 'center', 'right' }
-- The vertical anchor. 'bottom' means the y coordinate is the element's BOTTOM edge, so it
-- grows upward as its content gets taller instead of running off the screen.
local ANCHORS_Y = { 'top', 'bottom' }
-- Where an element may glue itself. A docked element ignores its own x/y and
-- follows the minimap rectangle, which is what keeps the shipped arrangement
-- together on an ultrawide and when the player moves the map.
-- `map-arc` is not listed: it is DERIVED by the client when the gauges are docked map-right
-- and the map is round, so it is never a stored value and accepting it here would let a
-- square map end up with an arc it has no circle for.
local DOCKS = { 'free', 'map-top', 'map-top-2', 'map-right', 'map-bottom' }

--- Take anything, return a settings table that is safe to apply and safe to store.
--- Never errors and never returns nil: the worst case is the server defaults.
function Settings.sanitise(input)
    local base = Settings.default()
    if type(input) ~= 'table' then return base end

    local out = HUD.merge(base, input)

    -- Theme. 'custom' is legal and means the player has drifted off a preset.
    if not Themes.allowed(out.theme) then out.theme = base.theme end

    -- Top-level scalars.
    out.compact = out.compact == true
    out.immersive = out.immersive == true
    out.cinematic = out.cinematic == true
    out.immersiveDelay = math.floor(clampTo(out.immersiveDelay, 'immersive', base.immersiveDelay))
    out.scale = clampTo(out.scale, 'scale', base.scale)
    out.opacity = clampTo(out.opacity, 'opacity', base.opacity)
    out.units = enum(out.units, UNITS, base.units)

    -- Element switches are booleans, no exceptions.
    for key, value in pairs(out.show) do
        out.show[key] = value == true
    end

    -- Style.
    out.style.gauge = enum(out.style.gauge, GAUGE_SHAPES, base.style.gauge)
    out.style.direction = enum(out.style.direction, DIRECTIONS, base.style.direction)
    out.style.icons = out.style.icons == true
    out.style.values = out.style.values == true
    out.style.hideFull = out.style.hideFull == true
    out.style.outline = out.style.outline == true
    out.style.glow = out.style.glow == true
    out.style.surface = enum(out.style.surface, SURFACES, base.style.surface)
    out.style.blur = math.floor(clampTo(out.style.blur, 'blur', base.style.blur))
    -- The neon theme uses 999 to mean "fully round", so the corner bound is the slider's
    -- range and 999 is allowed through as the one value above it.
    if tonumber(out.style.corner) ~= 999 then
        out.style.corner = math.floor(clampTo(out.style.corner, 'corner', base.style.corner))
    else
        out.style.corner = 999
    end
    out.style.gap = math.floor(clampTo(out.style.gap, 'gap', base.style.gap))

    -- Colours. Anything that is not six hex digits becomes the default for that key, which is
    -- what keeps a crafted payload out of the stylesheet.
    for key, value in pairs(out.colours) do
        out.colours[key] = HUD.colour(value, base.colours[key] or '#ffffff')
    end

    -- Positions.
    for key, position in pairs(out.positions) do
        if type(position) ~= 'table' then
            out.positions[key] = HUD.deepCopy(base.positions[key])
        else
            local fallback = base.positions[key]
                or { x = 50.0, y = 50.0, anchor = 'left', anchorY = 'top' }
            position.x = clampTo(position.x, 'positionX', fallback.x)
            position.y = clampTo(position.y, 'positionY', fallback.y)
            position.anchor = enum(position.anchor, ANCHORS, fallback.anchor)
            position.anchorY = enum(position.anchorY, ANCHORS_Y, fallback.anchorY or 'top')
            position.dock = enum(position.dock, DOCKS, fallback.dock or 'free')
        end
    end

    -- Minimap.
    out.minimap.shape = enum(out.minimap.shape, MAP_SHAPES, base.minimap.shape)
    out.minimap.borders = out.minimap.borders == true
    out.minimap.hide = out.minimap.hide == true
    out.minimap.vehicleOnly = out.minimap.vehicleOnly == true
    out.minimap.x = clampTo(out.minimap.x, 'minimapX', base.minimap.x)
    out.minimap.y = clampTo(out.minimap.y, 'minimapY', base.minimap.y)
    out.minimap.scale = clampTo(out.minimap.scale, 'minimapScale', base.minimap.scale)

    -- Speedometer.
    if not Speedometers.allowed(out.speedometer.style) then
        out.speedometer.style = base.speedometer.style
    end
    for _, key in ipairs({ 'fuel', 'rpm', 'gear', 'engine', 'belt', 'nitro', 'harness',
                           'altitude', 'range', 'odometer', 'parts' }) do
        out.speedometer[key] = out.speedometer[key] == true
    end

    -- Compass.
    out.compass.style = enum(out.compass.style, COMPASS_STYLES, base.compass.style)
    for _, key in ipairs({ 'degrees', 'pointer', 'cardinals', 'follow', 'vehicleOnly' }) do
        out.compass[key] = out.compass[key] == true
    end

    -- Street names.
    for _, key in ipairs({ 'crossing', 'zone', 'direction', 'vehicleOnly', 'uppercase', 'matchMap' }) do
        out.streets[key] = out.streets[key] == true
    end

    -- Advanced.
    for _, key in ipairs({ 'sounds', 'notifications', 'lowFuel' }) do
        out.advanced[key] = out.advanced[key] == true
    end

    -- The refresh rate has to be a rate the server actually offers, or the tick loop would
    -- index Config.Tick.rates with nil and fall back silently every single pass.
    if not (Config.Tick.rates or {})[out.advanced.refresh] then
        out.advanced.refresh = base.advanced.refresh
    end

    return out
end

--- Force everything the server decided. Runs LAST, so nothing above it - not a theme, not a
--- job override, not an imported settings code - can leave a policed value changed.
function Settings.applyPolicy(settings)
    local base = Settings.default()
    local policy = Config.Policy

    -- The player's protected values, put back at the end.
    --
    -- Locking a BRANCH forces every leaf under it, and two of those leaves are promised to
    -- the player. Locking `minimap` is a perfectly reasonable thing for an operator to want -
    -- it covers hide, scale and the offsets - but it must not drag `minimap.shape` with it.
    -- Rather than forbid the branch, the promised leaves are restored afterwards.
    local kept = {}
    for _, path in ipairs(NEVER_LOCKABLE) do
        kept[path] = HUD.deepCopy(Settings.getPath(settings, path))
    end

    -- A forced theme is applied in full first, so the colours and shapes that come with it
    -- land before anything else is pinned on top.
    if policy.forcedTheme and Themes[policy.forcedTheme] then
        settings = Themes.apply(settings, policy.forcedTheme)
    end

    if policy.forcedSpeedometer and Speedometers.allowed(policy.forcedSpeedometer) then
        settings.speedometer.style = policy.forcedSpeedometer
    end

    for key, value in pairs(policy.forcedStyle or {}) do
        if settings.style[key] ~= nil then settings.style[key] = value end
    end

    for key, value in pairs(policy.forcedColours or {}) do
        if settings.colours[key] ~= nil then
            settings.colours[key] = HUD.colour(value, settings.colours[key])
        end
    end

    -- Element policy. 'forced' is drawn whatever the player said; 'off' is never drawn, which
    -- is what makes it a removal rather than a default.
    for key, mode in pairs(policy.elements or {}) do
        if settings.show[key] ~= nil then
            if mode == 'forced' then settings.show[key] = true
            elseif mode == 'off' then settings.show[key] = false end
        end
    end

    --[[
        Then the locked paths, pinned back to the server default.

        `Settings.lockedPaths()` mixes two kinds of path, and they must not be treated alike:

          * paths the operator listed in Config.Policy.locked, and paths derived from a list
            narrowed to a single entry. These genuinely mean "hold this at the default", and
            for the narrowed lists this loop is the ONLY server-side enforcement there is -
            style.gauge, style.surface and compass.style are validated above against the full
            module constants rather than against the narrowed list, so removing them from this
            loop would let a crafted payload write a value the operator took away.

          * paths DERIVED from the forces just applied above - theme, speedometer.style,
            style.<key>, colours.<key>, show.<key>. Pinning those to `base` overwrites the
            force with the default, one statement after setting it.

        The second kind is why forcedTheme, forcedSpeedometer, forcedStyle, forcedColours and
        every 'forced'/'off' element silently did nothing at all. They are skipped here; the
        first kind is untouched, so nothing an operator restricted becomes reachable.

        lockedPaths() itself is unchanged, so the menu still draws a padlock on all of them.
    ]]
    local derived = {}

    if policy.forcedTheme and Themes[policy.forcedTheme] then derived['theme'] = true end
    if policy.forcedSpeedometer then derived['speedometer.style'] = true end
    for key in pairs(policy.forcedStyle or {}) do derived['style.' .. key] = true end
    for key in pairs(policy.forcedColours or {}) do derived['colours.' .. key] = true end
    for key, mode in pairs(policy.elements or {}) do
        if mode == 'forced' or mode == 'off' then derived['show.' .. key] = true end
    end

    for _, path in ipairs(Settings.lockedPaths()) do
        if not derived[path] then
            local forced = Settings.getPath(base, path)
            if forced ~= nil then
                Settings.setPath(settings, path, HUD.deepCopy(forced))
            end
        end
    end

    -- Give the player back what is theirs, whatever the branches above did to it.
    for path, value in pairs(kept) do
        if value ~= nil then Settings.setPath(settings, path, value) end
    end

    return settings
end

--- The full pipeline: merge, coerce, then force policy. This is what both sides call.
function Settings.normalise(input)
    return Settings.applyPolicy(Settings.sanitise(input))
end

-- ---------------------------------------------------------------------------------------
-- Layout presets
-- ---------------------------------------------------------------------------------------

--- The refresh rates this server offers, sorted, for the menu.
function Settings.refreshRates()
    local out = {}
    for rate in pairs(Config.Tick.rates or {}) do out[#out + 1] = rate end
    table.sort(out)
    return out
end

--- The presets this server offers, for the menu.
function Settings.layoutPresets()
    local out = {}
    for _, preset in ipairs(Config.LayoutPresets or {}) do
        out[#out + 1] = {
            key = preset.key,
            label = preset.label,
            positions = preset.positions,
            style = preset.style,
        }
    end
    return out
end

--- Move every element to `key`'s positions, leaving everything else alone. An unknown key
--- returns the input untouched rather than erroring.
function Settings.applyLayout(settings, key)
    for _, preset in ipairs(Config.LayoutPresets or {}) do
        if preset.key == key then
            local out = HUD.deepCopy(settings)
            out.positions = HUD.deepCopy(preset.positions)

            -- A preset may also set the gauge direction, because a layout built around a row
            -- of gauges does not fit a column of them. Nothing else about the player's style
            -- is touched.
            if preset.style then
                out.style = HUD.merge(out.style, preset.style)
            end

            return Settings.applyPolicy(Settings.sanitise(out))
        end
    end
    return settings
end

--- `settings` with a job or gang override laid on top. Never saved: the override is applied
--- at the point of use so that losing the job gives the player their own HUD back untouched.
function Settings.withJobOverride(settings, job, jobType, gang)
    local overrides = Config.JobOverrides or {}
    local patches = {}

    if job and overrides[job] then patches[#patches + 1] = overrides[job] end
    if jobType and overrides[jobType] then patches[#patches + 1] = overrides[jobType] end
    if gang and overrides['gang:' .. gang] then patches[#patches + 1] = overrides['gang:' .. gang] end

    if #patches == 0 then return settings end

    local out = settings
    for _, patch in ipairs(patches) do
        out = HUD.merge(out, patch)
    end

    -- A job override may not reach past the server's own policy.
    return Settings.applyPolicy(out)
end
