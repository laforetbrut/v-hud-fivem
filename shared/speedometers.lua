--[[
    shared/speedometers.lua

    The ten instrument clusters, as data. Each entry declares what the renderer needs to know
    about it - which readouts its face can actually show - and nothing about how it is drawn.
    The drawing lives in html/js/speedo.js, one builder per key.

    A face that cannot show a readout has that switch hidden in the menu rather than shown as
    a control that does nothing: `supports` is what the menu reads to decide.

    Every one of them is modelled on a real instrument cluster. Numbered graduations, a needle
    that sweeps a real arc, a redline where an engine has one, and a fuel gauge marked E to F.

    Shared so that the server validates a saved style name against the same list.
]]

Speedometers = {}

-- Order here is the order in the menu.
Speedometers.all = {
    {
        key = 'minimal',
        label = 'speedo.style_minimal',
        -- The current electric-car reading: the speed as a large numeral over a graduated arc,
        -- a fuel strip below. The face the Clear Glass theme uses.
        supports = { fuel = true, rpm = false, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 220, h = 118 },
    },
    {
        key = 'classic',
        label = 'speedo.style_classic',
        -- One round instrument, chrome bezel, cream face, numbered every 20. A car from
        -- before there were screens.
        supports = { fuel = true, rpm = false, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = false },
        size = { w = 168, h = 168 },
    },
    {
        key = 'sport',
        label = 'speedo.style_sport',
        -- Twin dials: tachometer with its redline on the left, speedometer on the right. The
        -- layout every sports car has used for forty years.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 280, h = 186 },
    },
    {
        key = 'digital',
        label = 'speedo.style_digital',
        -- A current digital cluster: horizontal rev bar with the redline picked out, big
        -- numerals, fuel and coolant strips.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 246, h = 150 },
    },
    {
        key = 'luxury',
        label = 'speedo.style_luxury',
        -- A thin, finely graduated ring with the speed printed inside it. The restrained
        -- German saloon reading of the same instrument.
        supports = { fuel = true, rpm = false, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 184, h = 184 },
    },
    {
        key = 'jdm',
        label = 'speedo.style_jdm',
        -- Tachometer first, speed second: a big rev counter with a shift light and the speed
        -- as a digital inset.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = false },
        size = { w = 192, h = 200 },
    },
    {
        key = 'muscle',
        label = 'speedo.style_muscle',
        -- Three gauges in a wide chrome-rimmed panel: fuel, speed, revs. An American dash,
        -- where the instruments are separate objects sitting in a bezel.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = false },
        size = { w = 296, h = 168 },
    },
    {
        key = 'supercar',
        label = 'speedo.style_supercar',
        -- Shift lights across the top, a central rev ring, and the speed as the only number
        -- that matters.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 208, h = 244 },
    },
    {
        key = 'truck',
        label = 'speedo.style_truck',
        -- Big, plain and complete: speed, revs, fuel and coolant, all four legible at a glance
        -- from a high seat.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 298, h = 214 },
    },
    {
        key = 'retro',
        label = 'speedo.style_retro',
        -- The 1980s answer: an LCD bar graph for speed with a numeric readout beside it, and a
        -- segmented rev ladder.
        supports = { fuel = true, rpm = true, gear = true, engine = true, belt = true, nitro = true, harness = true, altitude = true, range = true },
        size = { w = 252, h = 150 },
    },
}

local byKey = {}
for _, entry in ipairs(Speedometers.all) do
    byKey[entry.key] = entry
end

--- The speedometers this server offers, in Config.Policy order.
function Speedometers.list()
    local out = {}
    for _, key in ipairs(Config.Policy.speedometers) do
        local entry = byKey[key]
        if entry then out[#out + 1] = entry end
    end
    return out
end

--- Whether `key` is a speedometer this server allows.
function Speedometers.allowed(key)
    if type(key) ~= 'string' then return false end
    return byKey[key] ~= nil and HUD.oneOf(key, Config.Policy.speedometers)
end

--- The entry for `key`, or nil.
function Speedometers.get(key)
    return byKey[key]
end
