--[[
    themes/example.lua

    A theme, start to finish. Copy this file, rename it, change the values, add two lines to
    fxmanifest.lua and one to config.lua. That is the whole process - see THEMES.md.

    A theme is a PATCH, not a full settings table. It moves the keys it names and leaves
    everything else alone, which is why applying one never costs a player the layout they
    spent ten minutes arranging. Name only what your theme is actually opinionated about.

    Delete this file if you do not want it offered: it is listed explicitly in fxmanifest.lua,
    so removing it there is enough.
]]

Themes.example = {
    -- The identifier. Must match the table key above, and it is what goes in
    -- Config.Policy.themes to make the theme selectable.
    key = 'example',

    -- What the player sees in the picker. Written in your server's language.
    label = 'Example',

    -- Three colours for the card in the menu: usually background, accent, and a highlight.
    -- They are decoration only - nothing reads them but the picker.
    swatch = { '#101820', '#f2a900', '#4fc3ff' },

    patch = {
        style = {
            -- square | rounded | pill | circle | ring | radial | dot | bar | segment |
            -- diamond | hex | icon
            gauge = 'rounded',
            direction = 'column',        -- row | column
            icons = true,
            values = true,
            outline = true,
            glow = true,

            -- glass | tint | solid | none. `glass` is a translucent gradient with a lit edge;
            -- there is no real blur, and there cannot be - see THEMES.md.
            surface = 'tint',
            blur = 0,                    -- 0-32, only used by surface = 'glass'

            corner = 8,                  -- px. 999 means "fully round".
            gap = 8,                     -- px between gauges
        },

        -- Every colour is a six-digit hex. Anything else is refused and the default is kept,
        -- so a typo costs you one colour rather than the whole theme.
        colours = {
            accent     = '#f2a900',
            health     = '#4ade80',
            armor      = '#4fc3ff',
            hunger     = '#f2a900',
            thirst     = '#4fc3ff',
            stress     = '#c084fc',
            oxygen     = '#22d3ee',
            stamina    = '#a3e635',
            voice      = '#e2e8f0',
            speed      = '#ffffff',
            fuel       = '#fb923c',
            rpm        = '#f87171',
            warning    = '#ef4444',
            background = '#101820',
            text       = '#f8fafc',
        },

        -- Shape and border of the minimap frame. The player can still change the shape
        -- afterwards - that is one of the two promises this resource makes them.
        minimap = { shape = 'square', borders = true },

        -- One of the ten clusters: minimal, classic, sport, digital, luxury, jdm, muscle,
        -- supercar, truck, retro.
        speedometer = { style = 'digital' },

        -- bar | tape | dial | text
        compass = { style = 'bar' },
    },
}
