--[[
    shared/themes.lua

    A theme is a partial settings patch, nothing more. Selecting one runs it through
    HUD.merge over the player's current settings, so a theme only ever moves the keys it
    names and leaves positions, element toggles and the compass alone.

    That is deliberate: a player who has spent ten minutes dragging their HUD into place
    should be able to try Miami without losing the layout.

    Shared, because the server validates a theme name against the same table the client
    offers - the list cannot drift between the two sides.
]]

Themes = {}

-- The shipped default. Frosted glass over a Vice City sunset: translucent panels with a real
-- backdrop blur, a hot pink accent, cyan for anything that means "fine" and a magenta that
-- means "not fine". Everything glows, nothing is opaque.
--
-- The glass is `style.surface = 'glass'`, which is what switches the panels from a flat fill
-- to a blurred backdrop with a light edge. It is a setting rather than part of the theme's
-- colours because a player who wants the pink without the blur should be able to have it.
Themes.glass = {
    key = 'glass',
    label = 'Clear Glass',
    swatch = { '#1a0b26', '#ff4fa3', '#2de2e6' },
    patch = {
        style = {
            gauge = 'rounded',
            direction = 'column',
            icons = true,
            values = true,
            outline = true,
            glow = true,
            surface = 'glass',
            blur = 16,
            corner = 10,
            gap = 6,
        },
        colours = {
            accent     = '#ff4fa3',
            health     = '#2de2e6',
            armor      = '#8b5cf6',
            hunger     = '#ff9f4f',
            thirst     = '#4fc3ff',
            stress     = '#ff4fa3',
            oxygen     = '#2de2e6',
            stamina    = '#ffe66d',
            voice      = '#ffd6ec',
            speed      = '#ffffff',
            fuel       = '#ff8a3d',
            rpm        = '#ff2d6f',
            warning    = '#ff2d6f',
            background = '#1a0b26',
            text       = '#ffeaf6',
        },
        minimap = { shape = 'square', borders = true },
        -- The minimal cluster: a number over a graduated arc. The pink and the bloom come from
        -- the surface and the accent colour, so the instrument itself stays quiet.
        speedometer = { style = 'minimal' },
        compass = { style = 'bar' },
    },
}

-- Hard edges, one accent, no glow: everything is a rectangle and the only colour on screen is
-- the gauge fill.
Themes.square = {
    key = 'square',
    label = 'Carré minimaliste',
    swatch = { '#0b0f14', '#7dd3fc', '#4ade80' },
    patch = {
        style = {
            gauge = 'square',
            direction = 'column',
            icons = true,
            values = false,
            outline = true,
            glow = false,
            surface = 'solid',
            blur = 0,
            corner = 2,
            gap = 8,
        },
        colours = {
            accent     = '#7dd3fc',
            health     = '#4ade80',
            armor      = '#60a5fa',
            hunger     = '#fbbf24',
            thirst     = '#38bdf8',
            stress     = '#c084fc',
            oxygen     = '#22d3ee',
            stamina    = '#a3e635',
            voice      = '#e2e8f0',
            speed      = '#f8fafc',
            fuel       = '#fb923c',
            rpm        = '#f87171',
            warning    = '#ef4444',
            background = '#0b0f14',
            text       = '#f8fafc',
        },
        minimap = { shape = 'square', borders = true },
        -- The rectangular digital cluster, which is the square theme's shape in an instrument.
        speedometer = { style = 'digital' },
        compass = { style = 'bar' },
    },
}

-- Vice City sunset: hot pink into cyan over a deep indigo, rounded corners, glow on.
Themes.miami = {
    key = 'miami',
    label = 'Miami',
    swatch = { '#1a1033', '#ff4fa3', '#2de2e6' },
    patch = {
        style = {
            gauge = 'rounded',
            direction = 'column',
            icons = true,
            values = false,
            outline = false,
            glow = true,
            surface = 'tint',
            blur = 0,
            corner = 12,
            gap = 10,
        },
        colours = {
            accent     = '#ff4fa3',
            health     = '#2de2e6',
            armor      = '#7b61ff',
            hunger     = '#ffb35c',
            thirst     = '#4fc3ff',
            stress     = '#ff4fa3',
            oxygen     = '#2de2e6',
            stamina    = '#f9f871',
            voice      = '#ffd6ec',
            speed      = '#ffffff',
            fuel       = '#ff8a3d',
            rpm        = '#ff4fa3',
            warning    = '#ff2d6f',
            background = '#1a1033',
            text       = '#ffe9f5',
        },
        minimap = { shape = 'circle', borders = true },
        -- The 1980s LCD bar graph. A Vice City theme and a Countach cluster are the same idea.
        speedometer = { style = 'retro' },
        compass = { style = 'tape' },
    },
}

-- Black background, one saturated colour per gauge, everything outlined and glowing. The
-- loudest of the four and the one that reads best on a dark scene.
Themes.neon = {
    key = 'neon',
    label = 'Néon',
    swatch = { '#05070a', '#39ff14', '#00e5ff' },
    patch = {
        style = {
            gauge = 'circle',
            direction = 'column',
            icons = true,
            values = true,
            outline = true,
            glow = true,
            surface = 'none',
            blur = 0,
            corner = 999,
            gap = 12,
        },
        colours = {
            accent     = '#39ff14',
            health     = '#39ff14',
            armor      = '#00e5ff',
            hunger     = '#ffcc00',
            thirst     = '#00b3ff',
            stress     = '#ff00e5',
            oxygen     = '#00fff0',
            stamina    = '#c6ff00',
            voice      = '#ffffff',
            speed      = '#00e5ff',
            fuel       = '#ff9100',
            rpm        = '#ff003c',
            warning    = '#ff003c',
            background = '#05070a',
            text       = '#eaffea',
        },
        minimap = { shape = 'circle', borders = true },
        -- Shift lights and a rev ring: the loudest instrument for the loudest theme.
        speedometer = { style = 'supercar' },
        compass = { style = 'dial' },
    },
}

-- Slate and a single blue accent, soft corners, no glow. The one that disappears into the
-- game and does not fight the scene for attention.
Themes.modern = {
    key = 'modern',
    label = 'Modern',
    swatch = { '#111418', '#3b82f6', '#e5e7eb' },
    patch = {
        style = {
            gauge = 'bar',
            direction = 'column',
            icons = true,
            values = true,
            outline = false,
            glow = false,
            surface = 'tint',
            blur = 0,
            corner = 6,
            gap = 6,
        },
        colours = {
            accent     = '#3b82f6',
            health     = '#22c55e',
            armor      = '#3b82f6',
            hunger     = '#f59e0b',
            thirst     = '#0ea5e9',
            stress     = '#8b5cf6',
            oxygen     = '#06b6d4',
            stamina    = '#84cc16',
            voice      = '#9ca3af',
            speed      = '#e5e7eb',
            fuel       = '#f97316',
            rpm        = '#ef4444',
            warning    = '#dc2626',
            background = '#111418',
            text       = '#e5e7eb',
        },
        minimap = { shape = 'square', borders = false },
        -- The thin finely graduated ring: restrained, which is what this theme is for.
        speedometer = { style = 'luxury' },
        compass = { style = 'bar' },
    },
}

-- Themes the operator added in Config.ExtraThemes. Merged in rather than replacing, so a
-- config entry keyed 'square' customises the shipped square theme instead of shadowing it.
for key, extra in pairs(Config.ExtraThemes or {}) do
    local existing = Themes[key]
    Themes[key] = {
        key = key,
        label = extra.label or (existing and existing.label) or key,
        swatch = extra.swatch or (existing and existing.swatch) or { '#000000', '#ffffff', '#888888' },
        -- HUD.overlay, not HUD.merge: config.lua is trusted input and an operator's theme is
        -- allowed to name a colour the shipped theme never mentioned. The result still goes
        -- through Settings.sanitise before it reaches anything, so an unknown key is dropped
        -- there rather than here.
        patch = existing and HUD.overlay(existing.patch, extra.patch or {}) or (extra.patch or {}),
    }
end

--- The themes this server offers, in Config.Policy order, as an array the NUI can render
--- without knowing the table's key order.
---
--- A key in Config.Policy.themes with no theme behind it is reported rather than skipped in
--- silence: it is almost always a typo or a themes/ file missing from fxmanifest.lua, and a
--- theme that quietly does not appear is a miserable thing to chase.
local warnedMissing = {}

function Themes.list()
    local out = {}

    for _, key in ipairs(Config.Policy.themes or {}) do
        local theme = Themes[key]

        if theme then
            out[#out + 1] = {
                key = theme.key,
                label = theme.label,
                swatch = theme.swatch,
            }
        elseif not warnedMissing[key] then
            warnedMissing[key] = true
            HUD.warn(('Config.Policy.themes lists "%s", but no theme with that key exists. ' ..
                'Check the spelling, and that its file is in fxmanifest.lua.'):format(key))
        end
    end

    return out
end

--- Register a theme from another resource.
---
--- For a theme that ships with a server's own resource rather than living in v-hud's themes/
--- folder: `exports['v-hud']:RegisterTheme(key, definition)`. It becomes selectable as soon
--- as the key is in Config.Policy.themes.
function Themes.register(key, definition)
    if type(key) ~= 'string' or type(definition) ~= 'table' then return false end

    Themes[key] = {
        key = key,
        label = definition.label or key,
        swatch = definition.swatch or { '#000000', '#ffffff', '#888888' },
        patch = definition.patch or {},
    }

    warnedMissing[key] = nil
    return true
end

--- Whether `key` is a theme this server allows. Used on both sides; the server calls it on
--- an untrusted payload before saving.
function Themes.allowed(key)
    if type(key) ~= 'string' then return false end
    if key == 'custom' then return true end
    return Themes[key] ~= nil and HUD.oneOf(key, Config.Policy.themes)
end

--- `settings` with `key`'s patch applied. Returns the input untouched for an unknown theme,
--- so a bad name degrades to "nothing happened" rather than to an error.
function Themes.apply(settings, key)
    local theme = Themes[key]
    if not theme then return settings end

    local applied = HUD.merge(settings, theme.patch)
    applied.theme = key
    return applied
end
