--[[
    config.lua

    Every knob the server owner has, in one file.

    The file has two halves and the split is the whole design:

      * Config.Defaults is what a player STARTS with. They may change any of it from the menu.
      * Config.Policy is what a player MAY NOT change. Anything listed there is forced to the
        Config.Defaults value, greyed out with a padlock in the menu, and rejected server-side
        if a client sends it anyway.

    So "fully configurable by the player" and "the owner decides" are the same table read from
    two ends. An empty Policy.locked means the player owns everything, which is how it ships;
    adding a path takes exactly that path away and nothing else.

    Sections, in order:
        1  Language
        2  Opening the menu
        3  Where settings are stored
        4  Server policy: what is locked, what is offered, who may administer
        5  Job and gang overrides
        6  Admin presets
        6b Layout presets
        7  Status gauges - add your own here
        8  Money
        8b Notifications - and why qb-core, not the HUD, owns them
        9  Stress
        10 Cinematic mode
        11 Compatibility: what this resource uses if it finds it
        12 Refresh rates
        13 Extra themes
        14 Defaults - the starting point for every player
]]

Config = {}

-- =======================================================================================
-- 1. Language
-- =======================================================================================

-- Fallback language. Overridden by the `hud_locale` convar, then by `qb_locale`, so a server
-- that already set one language does not have to set a second.
--   setr hud_locale "fr"
Config.Locale = 'fr'

-- =======================================================================================
-- 2. Opening the menu
-- =======================================================================================

Config.Menu = {
    -- Key names: https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/
    -- An empty string registers no key mapping and leaves only the commands. The player can
    -- always rebind it in the GTA settings under FiveM once it is registered.
    key = 'I',

    -- The command that opens the menu.
    command = 'hud',

    -- qb-hud used `/menu`. Registered as well so muscle memory and old guides keep working.
    -- Set to an empty string to leave the name free for another resource.
    legacyCommand = 'menu',

    -- Close the menu on ESC as well as on the close button.
    closeOnEscape = true,

    -- The command that hides the WHOLE HUD - every element and the minimap - until it is
    -- typed again. For screenshots and cinema without touching any saved setting: the state
    -- is not persisted, so a relog brings the HUD back. Empty string registers no command.
    hideCommand = 'hidehud',

    -- Pause the game world behind the menu. Off by default: a HUD menu that freezes you in
    -- the middle of a firefight is a HUD menu nobody opens.
    freezeWhileOpen = false,
}

-- =======================================================================================
-- 3. Where settings are stored
-- =======================================================================================

Config.Persistence = {
    -- KVP is per-machine and instant. It is the primary store and it always runs: with it
    -- alone this resource has no dependency at all.
    kvp = true,

    -- The database copy makes settings follow the character to another machine. Optional,
    -- and it switches itself off when oxmysql is not started, so turning it on cannot break
    -- a server that does not have it.
    database = true,
    table = 'vhud_settings',

    -- Which side wins when the two disagree. 'newest' compares the saved timestamps, which
    -- is what you want; 'database' and 'kvp' force one side for a server that has an opinion.
    prefer = 'newest',

    -- Settings are per character by default (a citizenid each). Set to 'license' to make one
    -- HUD follow the player across all of their characters.
    scope = 'character',

    -- Milliseconds of quiet after the last change before a save is written. Dragging a colour
    -- slider fires a change per frame; without this each one would be a database round trip.
    debounce = 800,
}

-- =======================================================================================
-- 4. Server policy
-- =======================================================================================

Config.Policy = {
    -- Dotted paths into Config.Defaults. Each one is forced to its default value, shown
    -- greyed out with a padlock in the menu, and refused on save.
    --
    --   locked = {
    --       'theme',                 -- everyone runs the theme you chose
    --       'colours.background',    -- but they may still recolour their own gauges
    --       'minimap.hide',          -- nobody may hide the minimap
    --       'show.streets',          -- street names are mandatory
    --       'speedometer.style',
    --   },
    --
    -- Leave empty and the player owns every setting, which is the shipped position.
    locked = {},

    -- Themes offered in the menu. Remove one and it stops being selectable AND stops being
    -- accepted on save. The order here is the order in the menu.
    themes = { 'glass', 'square', 'miami', 'neon', 'modern' },

    -- Speedometers offered in the menu, same rules. All ten ship enabled, and every one of
    -- them is modelled on a real instrument cluster: numbered graduations, a needle on a real
    -- arc, a redline where an engine has one.
    speedometers = {
        'minimal', 'classic', 'sport', 'digital', 'luxury',
        'jdm', 'muscle', 'supercar', 'truck', 'retro',
    },

    -- Bounds the player's sliders may not leave. These exist so that "movable" cannot become
    -- "moved somewhere nobody can see it" on a server that cares.
    bounds = {
        scale        = { min = 0.60, max = 1.60 },
        opacity      = { min = 0.25, max = 1.00 },
        minimapX     = { min = -20.0, max = 20.0 },   -- percent of screen width
        minimapY     = { min = -20.0, max = 20.0 },   -- percent of screen height
        minimapScale = { min = 0.70, max = 1.50 },
        positionX    = { min = 0.0,  max = 100.0 },   -- percent of the viewport
        positionY    = { min = 0.0,  max = 100.0 },
        immersive    = { min = 2,    max = 30 },      -- seconds
        corner       = { min = 0,    max = 24 },      -- px
        gap          = { min = 0,    max = 32 },      -- px
        blur         = { min = 0,    max = 32 },      -- px, glass surface only
    },

    -- Ace permission required for /hudadmin. QBCore grants qbcore.admin to group.admin in the
    -- stock server.cfg, so this works out of the box on a default install.
    adminAce = 'qbcore.admin',

    -- Let an admin push a preset to a player or to everybody.
    allowAdminPush = true,

    -- Announce to the player when an admin changes their HUD. Off means it happens silently.
    announceAdminPush = true,
}

-- =======================================================================================
-- 5. Job and gang overrides
-- =======================================================================================

-- Settings forced on top of a player's own, for as long as they hold the job. They are
-- applied AFTER the player's settings and are not saved into them, so quitting the job gives
-- the player their own HUD back exactly as it was.
--
-- Keys are a job name, a job type, or `gang:<name>`.
Config.JobOverrides = {
    -- ['police'] = {
    --     show = { streets = true, compass = true },
    --     compass = { degrees = true },
    -- },
    -- ['ambulance'] = {
    --     show = { stress = false },
    -- },
    -- ['gang:ballas'] = {
    --     colours = { accent = '#7c3aed' },
    -- },
}

-- Whether a job override may touch a setting the player has set themselves. It cannot
-- override a Config.Policy.locked path either way - policy always wins.
Config.JobOverridesRespectPlayer = false

-- =======================================================================================
-- 6. Admin presets
-- =======================================================================================

-- Named settings patches an admin can push with `/hudadmin preset <name> <id|all>`. A preset
-- is a partial settings table: it moves the keys it names and leaves everything else alone.
Config.Presets = {
    ['minimal'] = {
        label = 'Minimal',
        patch = {
            compact = true,
            style = { values = false, icons = true, glow = false },
            show = { stamina = false, oxygen = false, voice = false },
        },
    },
    ['streamer'] = {
        label = 'Streamer',
        patch = {
            immersive = true,
            immersiveDelay = 4,
            show = { money = false },
            opacity = 0.85,
        },
    },
    ['roleplay'] = {
        label = 'Roleplay',
        patch = {
            immersive = true,
            compact = true,
            show = { speedometer = true, compass = false, streets = true },
            style = { values = false },
        },
    },
}

-- =======================================================================================
-- 6b. Layout presets
-- =======================================================================================

-- Named position sets, offered in the menu under Layout. Picking one moves every element at
-- once; the player can still drag anything afterwards.
--
-- Positions are a percentage of the viewport. `anchor` decides which edge of the element the
-- x coordinate refers to and `anchorY` the same for y. The vertical one matters more than it
-- looks: an element anchored to its TOP edge grows downward, and runs off the bottom of the
-- screen as soon as its content gets taller - which is what happens the moment a player picks
-- the tall supercar cluster or stacks bar gauges in a column. Anything sitting low on the
-- screen is anchored to its bottom edge instead, so it grows upward.
--
-- A preset may also carry a `style` patch. Positions and gauge direction are not independent:
-- a COLUMN of status gauges is 270px tall and a ROW of them is 40px, and an "everything down
-- the left edge" arrangement physically cannot hold a 270px column, a 244px cluster and four
-- other elements inside a 720px screen. So each preset names the direction it was laid out
-- for. Nothing else about the player's style is touched.
--
-- The client also clamps every element back inside the viewport after it renders, so a
-- combination nobody anticipated still cannot end up half off the screen.
--
-- The first entry is what a brand new player gets, and it must match Config.Defaults.positions
-- or the menu will show it as unselected on a fresh install.
Config.LayoutPresets = {
    {
        key = 'map',
        label = 'layout.preset_map',
        style = { direction = 'column' },
        positions = {
            streets = { dock = 'map-top',   x = 0.7,  y = 71.2, anchor = 'left',   anchorY = 'top' },
            voice   = { dock = 'map-top-2', x = 0.7,  y = 66.0, anchor = 'left',   anchorY = 'bottom' },
            status  = { dock = 'map-right', x = 19.5, y = 93.5, anchor = 'left',   anchorY = 'bottom' },
            speedo  = { dock = 'free', x = 98.5, y = 94.0, anchor = 'right',  anchorY = 'bottom' },
            compass = { dock = 'free', x = 50.0, y = 2.0,  anchor = 'center', anchorY = 'top' },
            vehicle = { dock = 'free', x = 98.5, y = 3.0,  anchor = 'right',  anchorY = 'top' },
        },
    },
    {
        key = 'classic',
        label = 'layout.preset_default',
        -- The qb-hud arrangement: gauges beside the map, street name across the top.
        style = { direction = 'row' },
        positions = {
            status  = { dock = 'map-right', x = 19.5, y = 93.5, anchor = 'left',   anchorY = 'bottom' },
            voice   = { dock = 'map-top',   x = 0.7,  y = 71.0, anchor = 'left',   anchorY = 'bottom' },
            streets = { dock = 'free', x = 50.0, y = 3.0,  anchor = 'center', anchorY = 'top' },
            speedo  = { dock = 'free', x = 98.5, y = 94.0, anchor = 'right',  anchorY = 'bottom' },
            compass = { dock = 'free', x = 50.0, y = 10.0, anchor = 'center', anchorY = 'top' },
            vehicle = { dock = 'free', x = 98.5, y = 3.0,  anchor = 'right',  anchorY = 'top' },
        },
    },
    {
        key = 'left',
        label = 'layout.preset_left',
        -- Everything stacked up the left edge, ABOVE the minimap: the bottom-left corner is
        -- the map's, and a column that runs into it is a column drawn over the map.
        --
        -- This is the tight case. Compass 48 + streets 47 + chips 24 + gauges 40 + voice 28 +
        -- the tallest cluster 274 is 461px of content, and at 720p there are 720px to put it
        -- in. Everything above the speedometer is therefore TOP-anchored and spaced from a
        -- 720p budget; at 1080p the same percentages simply leave more air. Only the
        -- speedometer is bottom-anchored, because it is the one element whose height changes
        -- with the player's choice and it has to grow into the empty middle.
        style = { direction = 'row' },
        positions = {
            compass = { dock = 'free', x = 1.5,  y = 1.7,  anchor = 'left', anchorY = 'top' },
            streets = { dock = 'free', x = 1.5,  y = 9.4,  anchor = 'left', anchorY = 'top' },
            vehicle = { dock = 'free', x = 1.5,  y = 18.0, anchor = 'left', anchorY = 'top' },
            status  = { dock = 'free', x = 1.5,  y = 24.0, anchor = 'left', anchorY = 'top' },
            voice   = { dock = 'free', x = 1.5,  y = 31.5, anchor = 'left', anchorY = 'top' },
            -- Docked, not free. "Everything on the left" and the minimap want the same corner,
            -- and the map wins - it is the one element whose position the game owns. So the
            -- speedometer sits directly ON TOP of the map and follows it, which is both the
            -- only place it fits and the only place it cannot be drawn over the map.
            speedo  = { dock = 'map-top', x = 1.5, y = 70.0, anchor = 'left', anchorY = 'bottom' },
        },
    },
    {
        key = 'right',
        label = 'layout.preset_right',
        -- The mirror of `left`, same 720p budget. This side has more room because the map is
        -- not in it, but the spacing is kept identical so the two read as a pair.
        style = { direction = 'row' },
        positions = {
            compass = { dock = 'free', x = 98.5, y = 1.7,  anchor = 'right', anchorY = 'top' },
            streets = { dock = 'free', x = 98.5, y = 9.4,  anchor = 'right', anchorY = 'top' },
            vehicle = { dock = 'free', x = 98.5, y = 18.0, anchor = 'right', anchorY = 'top' },
            status  = { dock = 'free', x = 98.5, y = 24.0, anchor = 'right', anchorY = 'top' },
            voice   = { dock = 'free', x = 98.5, y = 31.5, anchor = 'right', anchorY = 'top' },
            speedo  = { dock = 'free', x = 98.5, y = 97.2, anchor = 'right', anchorY = 'bottom' },
        },
    },
    {
        key = 'bottom',
        label = 'layout.preset_bottom',
        -- A centred bar along the bottom. The map keeps the left corner, so everything here
        -- is centred or right and none of it reaches back into it.
        style = { direction = 'row' },
        positions = {
            streets = { dock = 'free', x = 50.0, y = 88.0, anchor = 'center', anchorY = 'bottom' },
            status  = { dock = 'free', x = 50.0, y = 97.5, anchor = 'center', anchorY = 'bottom' },
            speedo  = { dock = 'free', x = 98.5, y = 80.0, anchor = 'right',  anchorY = 'bottom' },
            compass = { dock = 'free', x = 50.0, y = 2.0,  anchor = 'center', anchorY = 'top' },
            voice   = { dock = 'free', x = 98.5, y = 97.5, anchor = 'right',  anchorY = 'bottom' },
            vehicle = { dock = 'free', x = 98.5, y = 3.0,  anchor = 'right',  anchorY = 'top' },
        },
    },
    {
        key = 'corners',
        label = 'layout.preset_corners',
        -- Three corners, because the fourth is the minimap's.
        style = { direction = 'row' },
        positions = {
            status  = { dock = 'free', x = 1.5,  y = 3.0,  anchor = 'left',   anchorY = 'top' },
            voice   = { dock = 'free', x = 1.5,  y = 10.0, anchor = 'left',   anchorY = 'top' },
            streets = { dock = 'free', x = 50.0, y = 97.5, anchor = 'center', anchorY = 'bottom' },
            speedo  = { dock = 'free', x = 98.5, y = 94.0, anchor = 'right',  anchorY = 'bottom' },
            compass = { dock = 'free', x = 50.0, y = 2.0,  anchor = 'center', anchorY = 'top' },
            vehicle = { dock = 'free', x = 98.5, y = 3.0,  anchor = 'right',  anchorY = 'top' },
        },
    },
}

-- =======================================================================================
-- 7. Status gauges
-- =======================================================================================

-- The gauges down the side of the screen, as data. Add an entry and it appears in the HUD,
-- in the element list and in the colour picker with no code change anywhere.
--
--   key       identifier. Also the key under Config.Defaults.show and .colours.
--   icon      an inline SVG path, drawn at 24x24. Anything valid in a <path d="...">.
--   source    where the value comes from:
--               'native'    computed by client/main.lua (health, armor, oxygen, stamina)
--               'metadata'  read from the framework's player metadata, see `field`
--               'event'     pushed in by another resource, see API.md
--   field     the metadata key, for source = 'metadata'
--   invert    true when a HIGH value is bad (stress). Changes only the warning colour logic.
--   warnBelow the value under which the gauge takes the warning colour. nil disables it.
--   warnAbove the value over which the gauge takes the warning colour. nil disables it.
--   pulse     whether the gauge pulses while it is in its warning band.
--   order     display order, low first.
Config.Status = {
    {
        key = 'health', source = 'native', order = 10,
        icon = 'M12 21s-7.5-4.7-9.3-9A5.4 5.4 0 0 1 12 6.6 5.4 5.4 0 0 1 21.3 12c-1.8 4.3-9.3 9-9.3 9z',
        warnBelow = 25, pulse = true,
    },
    {
        key = 'armor', source = 'native', order = 20,
        icon = 'M12 2 4 5.3v6c0 5 3.4 9.7 8 10.7 4.6-1 8-5.7 8-10.7v-6L12 2z',
        warnBelow = nil, pulse = false,
    },
    {
        key = 'hunger', source = 'metadata', field = 'hunger', order = 30,
        icon = 'M7 2v9a3 3 0 0 0 3 3v8M7 2v6M10 2v6M17 2c-1.7 0-3 2.7-3 6s1.3 4 3 4v10',
        warnBelow = 25, pulse = true,
    },
    {
        key = 'thirst', source = 'metadata', field = 'thirst', order = 40,
        icon = 'M12 2.7 6.3 10a7 7 0 1 0 11.4 0L12 2.7z',
        warnBelow = 25, pulse = true,
    },
    {
        key = 'stress', source = 'metadata', field = 'stress', order = 50,
        icon = 'M13 2 4.5 13H11l-1 9 8.5-11H12l1-9z',
        invert = true, warnAbove = 60, pulse = true,
    },
    {
        key = 'oxygen', source = 'native', order = 60,
        icon = 'M12 21a5 5 0 0 0 5-5c0-2-1-3.4-2.5-5.5S12 6 12 3c0 3-1 5.4-2.5 7.5S7 14 7 16a5 5 0 0 0 5 5z',
        warnBelow = 30, pulse = true,
        -- Only drawn underwater. Set to false to keep it on screen permanently.
        onlyWhenRelevant = true,
    },
    {
        key = 'stamina', source = 'native', order = 70,
        icon = 'M6 4v16M18 4v16M6 12h12M3 8v8M21 8v8',
        warnBelow = nil, pulse = false,
        onlyWhenRelevant = true,
    },

    -- An example of adding your own. Uncomment, make sure something writes the metadata key,
    -- and the `show` switch and the colour well appear by themselves.
    -- {
    --     key = 'drunk', source = 'metadata', field = 'alcohol', order = 80,
    --     icon = 'M5 3h14l-6 8v7h3v3H8v-3h3v-7L5 3z',
    --     invert = true, warnAbove = 50, pulse = true,
    -- },
}

-- =======================================================================================
-- 8. Money
-- =======================================================================================

-- `/cash` and `/bank` only. There is no money element on this HUD: a balance parked on
-- screen all session is the first thing every player switches off, so it is not drawn, and
-- the passive "you gained $50" banner is not drawn either. A balance appears because it was
-- asked for, as a toast, and then it is gone.
Config.Money = {
    -- Prefix, suffix, or neither. `symbol` is drawn on the side you choose.
    symbol = '$',
    symbolPosition = 'prefix',      -- 'prefix' | 'suffix'

    -- Thousands separator. A space is the French convention; use ',' for the English one.
    thousands = ' ',

    -- How long the `/cash` and `/bank` toast stays on screen, in milliseconds.
    balanceDuration = 5000,

    -- Accounts the commands will answer for.
    accounts = { 'cash', 'bank' },
}

-- =======================================================================================
-- 8b. Notifications
-- =======================================================================================

-- IMPORTANT, because it is the most common misunderstanding about qb-hud: on a stock QBCore
-- server the notifications are NOT the HUD's. `QBCore.Functions.Notify` posts to qb-core's own
-- NUI page (qb-core/html/index.html), and the net event `QBCore:Notify` calls that same
-- function. Stopping qb-hud does not remove a single notification.
--
-- Which leaves a cosmetic problem: qb-core's notifications have their own hardcoded look and
-- will not follow the theme chosen here. The settings below are how far this resource is
-- willing to go about that.
Config.Notifications = {
    -- Draw this resource's own themed toast for anything that calls it directly:
    -- `exports['v-hud']:Notify(...)`, the HUD's own messages, and the server-side
    -- Bridge.notify fallback. Independent of everything below.
    own = true,

    -- Also render every `QBCore:Notify` in the HUD's theme.
    --
    -- Read this before turning it on. qb-core will STILL draw its own, so one event becomes
    -- two notifications. It is only useful together with the qb-core edit described in
    -- README > Notifications, which is three lines in qb-core/client/functions.lua and is
    -- yours to make or not. Off by default, because a resource should not double somebody's
    -- notifications by surprise.
    mirrorQbCore = false,

    -- Where the toasts stack.
    position = 'top-center',    -- top-center | top-right | top-left | bottom-center | bottom-right

    -- Default milliseconds on screen when the caller does not say.
    duration = 4000,

    -- How many are visible at once. Older ones are dropped rather than queued: a HUD is not a
    -- message log, and a queue means being told about something that happened four minutes ago.
    maxVisible = 4,

    -- Play the interact-sound click when one appears, if that resource is installed.
    sound = false,
}

-- =======================================================================================
-- 9. Stress
-- =======================================================================================

Config.Stress = {
    enabled = true,

    -- Percentage chance of gaining stress per shot fired. 0.1 is one shot in ten.
    shootingChance = 0.1,
    shootingAmount = { min = 1, max = 4 },

    -- Speed in the player's own unit at which speeding starts costing stress.
    speedBuckled = 100,
    speedUnbuckled = 50,
    speedAmount = { min = 1, max = 3 },
    speedInterval = 10000,

    -- Stress level at which the screen starts to shake and blur.
    effectMinimum = 50,

    -- Jobs, job types and gangs that never gain stress. Keys are matched against the job
    -- name, the job type, and `gang:<name>`.
    exemptJobs = {
        ['leo'] = true,
        ['police'] = true,
        ['ambulance'] = true,
    },

    -- Vehicle classes that can cause speeding stress.
    vehicleClasses = {
        [0] = true,  [1] = true,  [2] = true,  [3] = true,  [4] = true,
        [5] = true,  [6] = true,  [7] = true,  [8] = true,  [9] = true,
        [10] = true, [11] = true, [12] = true,
        [13] = false,                     -- Cycles
        [14] = false,                     -- Boats
        [15] = false,                     -- Helicopters
        [16] = false,                     -- Planes
        [17] = false,                     -- Service
        [18] = false,                     -- Emergency
        [19] = false,                     -- Military
        [20] = false,                     -- Commercial
        [21] = false,                     -- Trains
    },

    -- Vehicles that never cause speeding stress, by model hash.
    exemptVehicles = {
        -- [`adder`] = true,
    },

    -- Weapons that never cause stress when fired.
    exemptWeapons = {
        [`weapon_petrolcan`] = true,
        [`weapon_hazardcan`] = true,
        [`weapon_fireextinguisher`] = true,
        [`weapon_fertilizercan`] = true,
    },

    -- Weapons that do not light the "armed" marker. Anything you carry rather than aim.
    unarmedLike = {
        [`weapon_petrolcan`] = true,
        [`weapon_hazardcan`] = true,
        [`weapon_fireextinguisher`] = true,
        [`weapon_fertilizercan`] = true,
        [`weapon_dagger`] = true,
        [`weapon_bat`] = true,
        [`weapon_bottle`] = true,
        [`weapon_crowbar`] = true,
        [`weapon_flashlight`] = true,
        [`weapon_golfclub`] = true,
        [`weapon_hammer`] = true,
        [`weapon_hatchet`] = true,
        [`weapon_knuckle`] = true,
        [`weapon_knife`] = true,
        [`weapon_machete`] = true,
        [`weapon_switchblade`] = true,
        [`weapon_nightstick`] = true,
        [`weapon_wrench`] = true,
        [`weapon_battleaxe`] = true,
        [`weapon_poolcue`] = true,
        [`weapon_briefcase`] = true,
        [`weapon_briefcase_02`] = true,
        [`weapon_garbagebag`] = true,
        [`weapon_handcuffs`] = true,
        [`weapon_bread`] = true,
        [`weapon_stone_hatchet`] = true,
        [`weapon_grenade`] = true,
        [`weapon_bzgas`] = true,
        [`weapon_molotov`] = true,
        [`weapon_stickybomb`] = true,
        [`weapon_proxmine`] = true,
        [`weapon_snowball`] = true,
        [`weapon_pipebomb`] = true,
        [`weapon_ball`] = true,
        [`weapon_smokegrenade`] = true,
        [`weapon_flare`] = true,
    },

    -- Screen shake and blur by stress band. Read top to bottom; the first band whose range
    -- contains the current stress wins.
    effects = {
        { min = 50, max = 60,  blur = 1500, interval = { 50000, 60000 }, shake = 0.06 },
        { min = 60, max = 70,  blur = 2000, interval = { 40000, 50000 }, shake = 0.10 },
        { min = 70, max = 80,  blur = 2500, interval = { 30000, 40000 }, shake = 0.16 },
        { min = 80, max = 90,  blur = 2700, interval = { 20000, 30000 }, shake = 0.22 },
        { min = 90, max = 101, blur = 3000, interval = { 15000, 20000 }, shake = 0.30 },
    },
}

-- =======================================================================================
-- 10. Cinematic mode
-- =======================================================================================

Config.Cinematic = {
    -- Height of each black bar, as a fraction of the screen.
    barHeight = 0.12,

    -- Milliseconds the bars take to slide in and out.
    animation = 400,

    -- Hide the minimap while the bars are down.
    hideMinimap = true,

    -- Hide the whole HUD, not only the minimap.
    hideHud = true,

    -- Command name. Empty string registers no command.
    command = 'cinematic',
}

-- =======================================================================================
-- 11. Compatibility
-- =======================================================================================

-- Everything here is DETECTED, never required. A provider that is not started is skipped and
-- the next one in the list is tried. Nothing in this section can stop the HUD from loading.
Config.Compat = {
    -- Fuel providers, in preference order. The first started resource wins.
    --
    -- Each entry names the resource and how to read a percentage out of it, because they do
    -- not agree: rcore_fuel returns a percentage from its own export, qb-fuel and the
    -- LegacyFuel family return 0-100 from GetFuel, and ox_fuel writes a state bag instead of
    -- exporting anything.
    --
    -- Set `Config.Compat.forceFuel = 'rcore_fuel'` to skip detection entirely.
    fuel = {
        {
            resource = 'rcore_fuel',
            -- https://documentation.rcore.cz/paid-resources/rcore_fuel/api/client
            kind = 'export',
            percent = 'GetVehicleFuelPercentage',
            -- Optional extras. Present only on rcore_fuel; the speedometer shows the range
            -- readout when they answer and hides it when they do not.
            litres = 'GetVehicleFuelLiters',
            capacity = 'GetMaximumFuelCapacityForVehicle',
            range = 'GetVehicleMaxCurrentDrivingRange',
            efficiency = 'GetVehicleFuelConsumptionEfficiency',
        },
        { resource = 'qb-fuel',        kind = 'export', percent = 'GetFuel' },
        { resource = 'LegacyFuel',     kind = 'export', percent = 'GetFuel' },
        { resource = 'ps-fuel',        kind = 'export', percent = 'GetFuel' },
        { resource = 'cdn-fuel',       kind = 'export', percent = 'GetFuel' },
        { resource = 'lc_fuel',        kind = 'export', percent = 'GetFuel' },
        { resource = 'x-fuel',         kind = 'export', percent = 'GetFuel' },
        { resource = 'okokGasStation', kind = 'export', percent = 'GetFuel' },
        { resource = 'Renewed-Fuel',   kind = 'export', percent = 'GetFuel' },
        { resource = 'ox_fuel',        kind = 'statebag', bag = 'fuel' },
        -- Always last and always works: GetVehicleFuelLevel straight off the vehicle.
        { resource = 'native',         kind = 'native' },
    },

    -- Skip fuel detection and use this resource name. nil means detect.
    forceFuel = nil,

    -- Milliseconds between fuel reads. Fuel moves slowly and an export call is not free.
    fuelInterval = 2000,

    -- Percentage below which the low-fuel warning fires, and how often it repeats.
    lowFuelAt = 20,
    lowFuelRepeat = 60000,

    -- Show the remaining range next to the fuel gauge when the fuel provider can work it out.
    showRange = true,

    -- Voice. Detected, never required. Sets the voice range rings and the talking indicator.
    voice = { 'pma-voice', 'saltychat', 'mumble-voip' },
    forceVoice = nil,

    -- Notifications. The first one started is used; 'native' draws the HUD's own toast.
    notify = { 'qb-core', 'ox_lib', 'okokNotify', 'native' },
    forceNotify = nil,

    -- Menu sound effects, played through interact-sound when it is installed. Silent when it
    -- is not: the menu never depends on a sound resource being there.
    sounds = { 'interact-sound', 'InteractSound' },

    -- Inventories the harness check can read. The first one that answers wins; when none do,
    -- the harness ring simply never lights.
    inventory = { 'qb-inventory', 'ox_inventory', 'qs-inventory', 'ps-inventory', 'origen_inventory', 'codem-inventory', 'core_inventory' },
    forceInventory = nil,

    -- The item whose presence lights the harness ring.
    harnessItem = 'harness',

    -- Seatbelt and cruise control events this HUD listens for. Add your own resource's event
    -- name and the belt indicator starts working with no code change.
    seatbeltEvents = {
        'seatbelt:client:ToggleSeatbelt',
        'qb-smallresources:client:ToggleSeatbelt',
        'hud:client:ToggleSeatbelt',
    },
    cruiseEvents = {
        'seatbelt:client:ToggleCruise',
        'qb-smallresources:client:ToggleCruise',
        'hud:client:ToggleCruise',
    },
    -- Some seatbelt scripts publish a state bag instead of an event. Checked as well as the
    -- events above; whichever answers first wins.
    seatbeltStateBag = 'seatbelt',

    -- Nitrous. Three sources, all optional, first answer wins:
    --
    --   * Events. qb-mechanicjob, qb-tunerjob and jim-mechanic all fire the qb-hud event
    --     `hud:client:UpdateNitrous` with the level; the jim- prefixed name is listened for
    --     as well in case a build fires its own.
    --   * Entity state bags. jim-mechanic stores `hasnitro` and `noslevel` per vehicle
    --     (the same columns it keeps in player_vehicles), so a fresh entry into a NOS-fitted
    --     car shows the bottle level before any event has fired.
    --
    -- The gauge takes whichever spoke last, so an event-driven boost still animates live
    -- even on a server where the bag only updates on save.
    nitroEvents = {
        'hud:client:UpdateNitrous',
        'vhud:client:UpdateNitrous',
        'jim-mechanic:client:UpdateNitrous',
    },
    nitroStateBags = { 'noslevel', 'noslevel:level', 'jimNos' },
    nitroHasBags = { 'hasnitro', 'jimHasNos' },

    -- Answer the qb-hud events so that every stock qb resource keeps working with this HUD
    -- installed and qb-hud stopped. Turn off only if you still run qb-hud alongside, which
    -- is not a supported configuration.
    qbHudEvents = true,

    -- Publish the `hud:server:getMenu` callback qb-hud owned, so a third-party resource that
    -- asks for it gets an answer instead of a timeout.
    qbHudCallback = true,
}

-- =======================================================================================
-- 12. Refresh rates
-- =======================================================================================

Config.Tick = {
    -- The HUD refresh rate the player picks, in frames per second, and the Wait() each one
    -- costs. Every entry here is offered in the menu, so removing one removes the choice.
    --
    -- 60 is the default and is what a HUD should feel like. 30 halves the work for a machine
    -- that needs the frames back; 90 exists for a high refresh monitor where 60 is visible as
    -- a stepping gauge. Above 90 there is nothing left to see - the values themselves only
    -- change a few times a second.
    rates = {
        [30] = 33,
        [60] = 16,
        [90] = 11,
    },
    defaultRate = 60,

    -- The compass and the street names run on their own slower loops: a heading recomputed at
    -- the HUD rate reads as jitter, not as smoothness, and a street name changes when you
    -- cross a junction and at no other time.
    compass = 100,
    streets = 500,

    -- How often the harness item check runs.
    inventory = 2000,
}

-- =======================================================================================
-- 13. Extra themes
-- =======================================================================================

-- Themes defined here are merged into the five shipped ones. A theme is a partial settings
-- patch: it moves the keys it names and leaves the player's positions and element toggles
-- alone, so trying a theme never costs somebody the layout they spent ten minutes on.
--
-- Add the key to Config.Policy.themes as well or it will not be offered.
Config.ExtraThemes = {
    -- ['midnight'] = {
    --     label = 'Midnight',
    --     swatch = { '#04060d', '#5b8cff', '#8be9fd' },
    --     patch = {
    --         style = { gauge = 'rounded', glow = false, corner = 8, surface = 'tint' },
    --         colours = { accent = '#5b8cff', background = '#04060d', text = '#dbe6ff' },
    --         minimap = { shape = 'square', borders = true },
    --         speedometer = { style = 'luxury' },
    --         compass = { style = 'bar' },
    --     },
    -- },
}

-- =======================================================================================
-- 14. Defaults
-- =======================================================================================

-- What a new player gets, and what a locked setting is forced to.
Config.Defaults = {
    -- One of Config.Policy.themes, or 'custom' once the player has touched anything a theme
    -- owns. The shipped default is the frosted glass one: translucent panels, hot pink
    -- accent, Vice City palette.
    theme = 'glass',

    compact = false,
    immersive = false,
    immersiveDelay = 6,          -- seconds of nothing happening before the HUD fades
    scale = 1.0,
    opacity = 1.0,
    units = 'kmh',               -- 'kmh' | 'mph'
    cinematic = false,

    -- Every drawable element. Off means not drawn AND not computed.
    show = {
        health = true,
        armor = true,
        hunger = true,
        thirst = true,
        stress = true,
        oxygen = true,
        stamina = true,
        voice = true,
        speedometer = true,
        -- OFF. A compass strip across the top of the screen is a strong opinion to impose on
        -- everybody; the players who want one turn it on in two clicks.
        compass = false,
        streets = true,
        minimap = true,
        nitro = true,
        harness = true,
        engine = true,
        seatbelt = true,
        parachute = true,
        armed = true,
        dev = true,
    },

    style = {
        -- Twelve shapes: square, rounded, pill, circle, ring, radial, dot, bar, segment,
        -- diamond, hex, icon.
        gauge = 'rounded',
        direction = 'column',    -- row | column
        icons = true,
        values = true,
        hideFull = false,
        outline = true,
        glow = true,

        -- How a panel is filled behind its content.
        --   glass  translucent with a real backdrop blur and a light edge
        --   tint   translucent, no blur - the cheap version of glass
        --   solid  opaque
        --   none   no panel at all, only the shapes and their glow
        surface = 'glass',
        blur = 16,               -- px, only used by surface = 'glass'

        corner = 10,             -- px
        gap = 6,                 -- px
    },

    -- The Clear Glass palette. Every one of these is a colour well in the menu.
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

    -- Percentages of the viewport, with a named anchor on each axis. See the note above
    -- Config.LayoutPresets for why the vertical one matters.
    --
    -- The shipped arrangement is built around the minimap: the street banner sits directly on
    -- top of it at the same width, and the status gauges stack up its right-hand edge.
    positions = {
        -- `dock` glues an element to an edge of the minimap and makes its x/y unused. That
        -- is the shipped arrangement: the street banner is the lid of the map, the voice
        -- indicator sits above it, and the gauges stack up the map's right-hand side.
        --
        -- Docking is not the same as a percentage that happens to land near the map. The map
        -- is sized from the screen HEIGHT; a percentage of the WIDTH drifts off it on any
        -- aspect ratio but 16:9, and stops tracking entirely when the player moves or
        -- resizes the map. A docked element follows it on every screen.
        --
        -- 'free' uses x/y instead. Dragging an element in the editor sets it to 'free', and
        -- the x/y kept beside each dock is where it lands when that happens.
        streets = { dock = 'map-top',   x = 0.7,  y = 71.2, anchor = 'left',   anchorY = 'top' },
        voice   = { dock = 'map-top-2', x = 0.7,  y = 66.0, anchor = 'left',   anchorY = 'bottom' },
        status  = { dock = 'map-right', x = 19.5, y = 93.5, anchor = 'left',   anchorY = 'bottom' },
        speedo  = { dock = 'free', x = 98.5, y = 94.0, anchor = 'right',  anchorY = 'bottom' },
        compass = { dock = 'free', x = 50.0, y = 2.0,  anchor = 'center', anchorY = 'top' },
        vehicle = { dock = 'free', x = 98.5, y = 3.0,  anchor = 'right',  anchorY = 'top' },
    },

    minimap = {
        shape = 'square',        -- square | circle
        borders = true,
        x = 0.0,                 -- percent of screen width
        y = 0.0,                 -- percent of screen height
        scale = 1.0,
        hide = false,
        vehicleOnly = false,
    },

    speedometer = {
        style = 'minimal',       -- one of Config.Policy.speedometers
        fuel = true,
        rpm = true,
        gear = true,
        engine = true,
        belt = true,
        nitro = true,
        harness = true,
        altitude = true,
        range = true,            -- remaining range, when the fuel provider can work it out
    },

    compass = {
        style = 'bar',           -- bar | tape | dial | text
        degrees = true,
        pointer = true,
        cardinals = true,
        follow = true,           -- read the camera rather than the ped
        vehicleOnly = false,
    },

    streets = {
        crossing = true,
        zone = true,
        direction = true,
        vehicleOnly = false,
        uppercase = false,
        -- Stretch the banner to exactly the minimap's width and follow it when the player
        -- resizes or moves the map. This is what makes the shipped layout look built rather
        -- than arranged: the banner is the lid of the map, not a box floating near it.
        matchMap = true,
    },

    advanced = {
        -- HUD refresh rate in frames per second. One of the keys in Config.Tick.rates.
        refresh = 60,
        sounds = true,
        notifications = true,
        lowFuel = true,
    },
}
