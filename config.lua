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

    ---------------------------------------------------------------------------------------
    HOW TO READ THIS FILE
    ---------------------------------------------------------------------------------------

    Nothing here has to be changed. It runs correctly as shipped on a stock QBCore server, and
    every section explains what it costs to change and what breaks if you get it wrong.

    Each setting is written as: what it does, then WHY it defaults to what it does. When the
    reason is a bug that was actually hit, the comment says so - those are the settings where
    a plausible-looking change will cost you an evening.

    ---------------------------------------------------------------------------------------
    THE FIVE THINGS OWNERS CHANGE FIRST
    ---------------------------------------------------------------------------------------

        Config.Locale                     the language                       (section 1)
        Config.Policy.forcedTheme         one look for everybody             (section 4)
        Config.Policy.elements            remove a gauge server-wide         (section 4)
        Config.HideWhen                   when the HUD steps aside for menus (section 10b)
        Config.Defaults                   what a new player starts with      (section 14)

    ---------------------------------------------------------------------------------------
    SECTIONS, IN ORDER
    ---------------------------------------------------------------------------------------

        1   Language
        2   Opening the menu
        3   Where settings are stored
        4   Server policy: what is locked, what is offered, who may administer
        5   Job and gang overrides
        6   Admin presets
        6b  Layout presets
        7   Status gauges - add your own here
        8   Money
        8b  Notifications - and why qb-core, not the HUD, owns them
        9   Stress
        10  Cinematic mode
        10a Compatibility: what this resource uses if it finds it
        10a-ter Cluster thresholds - when the warning lamps light
        10a-bis Driving warnings - the sounds
        10b When the HUD gets out of the way  <- read this one if a menu misbehaves
        11b Odometer
        12  Refresh rates
        13  Extra themes
        14  Defaults - the starting point for every player
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

-- Two promises this resource makes to PLAYERS, which no setting below can take away:
--
--   1. They can always move every element. Positions and docking are never lockable.
--   2. They can always choose the minimap shape, square or round.
--
-- Both are enforced in code, not by convention: `Settings.isLocked` refuses those paths and
-- the server prints a warning if a config tries to lock them. Everything else is yours.
Config.Policy = {

    -- --- What is offered -----------------------------------------------------------------

    -- Themes offered in the menu. Remove one and it stops being selectable AND stops being
    -- accepted on save. The order here is the order in the menu. An empty list leaves the
    -- player on whatever `Config.Defaults.theme` says, with no picker at all.
    themes = { 'glass', 'square', 'miami', 'neon', 'modern' },

    -- Speedometers offered in the menu, same rules. All ten ship enabled, and every one of
    -- them is modelled on a real instrument cluster: numbered graduations, a needle on a real
    -- arc, a redline where an engine has one.
    speedometers = {
        'minimal', 'classic', 'sport', 'digital', 'luxury',
        'jdm', 'muscle', 'supercar', 'truck', 'retro',
    },

    -- Gauge shapes offered under Style. Twelve ship; cut the list to impose a house look
    -- without locking the setting outright.
    gaugeShapes = {
        'square', 'rounded', 'pill', 'circle', 'ring', 'radial',
        'dot', 'bar', 'segment', 'diamond', 'hex', 'icon',
    },

    -- Compass styles offered. An EMPTY list removes the compass from the server entirely -
    -- no element, no tab, nothing computed.
    compassStyles = { 'bar', 'tape', 'dial', 'text' },

    -- Panel surfaces offered under Style.
    surfaces = { 'glass', 'tint', 'solid', 'none' },

    -- --- What is forced ------------------------------------------------------------------

    -- Everyone runs this theme and the picker is locked. nil lets them choose.
    --   forcedTheme = 'glass',
    forcedTheme = nil,

    -- Everyone runs this cluster and the picker is locked. nil lets them choose.
    --   forcedSpeedometer = 'digital',
    forcedSpeedometer = nil,

    -- Style values imposed on everyone, whatever theme they pick. Any key of
    -- Config.Defaults.style. Each one is forced on save and greyed out in the menu.
    --
    --   forcedStyle = { surface = 'solid', glow = false, corner = 4 },
    forcedStyle = {},

    -- Colours imposed on everyone. Any key of Config.Defaults.colours.
    --
    --   forcedColours = { accent = '#ff0044', background = '#0a0a0a' },
    forcedColours = {},

    -- --- What each element may do --------------------------------------------------------

    -- One entry per drawable element. Three answers:
    --
    --   'player'  the player decides. The switch is in the menu. (default)
    --   'forced'  always drawn. The switch is shown locked.
    --   'off'     never drawn on this server. Removed from the menu and never computed -
    --             this is how you delete an element rather than merely defaulting it off.
    --
    -- Anything not listed here is 'player'. A gauge added to Config.Status can be listed too.
    elements = {
        health      = 'player',
        armor       = 'player',
        hunger      = 'player',
        thirst      = 'player',
        stress      = 'player',
        oxygen      = 'player',
        stamina     = 'player',
        voice       = 'player',
        speedometer = 'player',
        compass     = 'player',
        streets     = 'player',
        minimap     = 'player',
        nitro       = 'player',
        harness     = 'player',
        engine      = 'player',
        seatbelt    = 'player',
        parachute   = 'player',
        armed       = 'player',
        dev         = 'player',
    },

    -- --- Anything else -------------------------------------------------------------------

    -- Dotted paths into Config.Defaults, for whatever the switches above do not cover. Each
    -- one is forced to its default value, shown greyed out with a padlock, and refused on
    -- save.
    --
    --   locked = {
    --       'colours.background',    -- but they may still recolour their own gauges
    --       'minimap.hide',          -- nobody may hide the minimap
    --       'advanced.refresh',      -- everyone runs the rate you chose
    --       'units',                 -- km/h only
    --   },
    --
    -- Two paths are REFUSED here and always will be: `positions` and `minimap.shape`. See the
    -- note above this table.
    locked = {},

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

    -- Let players export their settings as a shareable code, and paste somebody else's in.
    -- The pasted settings go through exactly the same validation as any other save, so an
    -- import can never carry a locked value or an unknown key past the policy above.
    allowSharing = true,

    -- An imported code brings the LOOK and leaves the LAYOUT alone: the colours, shapes,
    -- cluster and theme arrive, the positions the player arranged stay where they are.
    -- Set to false to let an import move their elements too.
    importKeepsLayout = true,
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
            -- 13%, not 10%. The banner above it is 47 FIXED pixels tall while this gap is a
            -- percentage, so the clearance shrinks with the screen: 10% left three pixels at
            -- 720p and overlapped outright below it.
            compass = { dock = 'free', x = 50.0, y = 13.0, anchor = 'center', anchorY = 'top' },
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

    -- ---------------------------------------------------------------------------------
    -- Framework
    -- ---------------------------------------------------------------------------------
    --
    -- Detected automatically, in this order: qb-core, qbx_core, es_extended, ox_core. The
    -- first one whose resource is started AND whose handshake answers is used, and anything
    -- else runs standalone - settings still save to the client's own storage, stress is not
    -- persisted, and nothing errors.
    --
    -- Set this to a resource name to skip detection on a server that has two installed, for
    -- example a qb-core server keeping es_extended around for one legacy script:
    --
    --     forceFramework = 'qb-core',
    --
    -- WHAT DIFFERS BETWEEN THEM, so you know what to expect:
    --
    --   qb-core / qbx_core   everything works: jobs, gangs, metadata, notifications,
    --                        chat suggestions on the commands.
    --
    --   es_extended (ESX)    no gang, so Config.JobOverrides keys of the form 'gang:name'
    --                        never match. The job GRADE is exposed where qb-core exposes the
    --                        job type, which is the closest equivalent to key an override on.
    --                        Hunger and thirst come from esx_status rather than from player
    --                        metadata; the HUD listens to it directly.
    --
    --   ox_core              groups instead of jobs: the first group is reported as the job
    --                        name and its rank as the type. No notification system of its
    --                        own, so HUD notifications use the HUD's own toast.
    forceFramework = nil,

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
    --
    -- ox_core is deliberately absent: it ships no notification system, so a server running it
    -- falls through to 'native' and gets the HUD's own themed toast. That is the right answer
    -- on that framework rather than a compromise.
    notify = { 'qb-core', 'es_extended', 'ox_lib', 'okokNotify', 'native' },
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

    -- Scripts that answer "is the belt on" directly. THIS IS THE BEST SOURCE and it is tried
    -- first, because it cannot drift: the HUD asks the seatbelt script what it thinks instead
    -- of trying to mirror it from events.
    --
    -- Mirroring is fragile in a way that is easy to miss. qb-smallresources' own harness path
    -- is the example: putting a harness ON fires the seatbelt event, taking it OFF returns
    -- early and fires nothing, so anything keeping its own copy is stuck showing a belt that
    -- was taken off. Asking the export gives the right answer with no such holes.
    --
    -- Each entry is a resource and a boolean export on it. Missing resources and missing
    -- exports are skipped, and the events and the state bag remain as fallbacks.
    seatbeltExports = {
        { resource = 'qb-smallresources', method = 'HasSeatbeltOn' },
        { resource = 'seatbelt', method = 'HasSeatbeltOn' },
        { resource = 'qb-seatbelt', method = 'HasSeatbeltOn' },
    },

    harnessExports = {
        { resource = 'qb-smallresources', method = 'HasHarness' },
    },

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

    -- ---------------------------------------------------------------------------------
    -- Mechanical wear, for the dashboard tell-tales
    -- ---------------------------------------------------------------------------------
    --
    -- A real cluster warns you about the brakes, the coolant and the driveline. GTA tracks
    -- none of that, so it comes from whichever mechanic script is installed - or from nowhere,
    -- in which case those lamps simply never light.
    --
    -- Turn the whole thing off here if you do not run a mechanic script and want the tick a
    -- little cheaper.
    parts = true,

    -- How often the plate-keyed callback below is re-asked, in milliseconds. Wear changes when
    -- a mechanic works on the car, not while you drive, so this can be slow.
    partsRefresh = 30000,

    -- Vehicle STATE BAGS to read first, per part. Free, current, and no round trip - this is
    -- how a mechanic script publishes wear when it wants other resources to see it.
    --
    -- The part names on the left are this HUD's; the bag names on the right are whatever your
    -- script writes. Add yours to the list rather than replacing it: the first bag that holds
    -- a number wins, and an unknown bag costs nothing.
    partBags = {
        brakes       = { 'brakes', 'jimBrakes', 'vehicleBrakes' },
        clutch       = { 'clutch', 'jimClutch' },
        radiator     = { 'radiator', 'jimRadiator', 'coolant' },
        axle         = { 'axle', 'jimAxle', 'driveshaft' },
        injector     = { 'fuel', 'injector', 'jimInjector', 'fuelPump' },
        transmission = { 'transmission', 'jimTransmission', 'gearbox' },
        electronics  = { 'electronics', 'battery', 'jimBattery' },
        suspension   = { 'suspension', 'jimSuspension' },
    },

    -- Fallback: a framework callback keyed on the number plate.
    --
    -- qb-mechanicjob keeps its wear table server-side in `vehicleComponents[plate]` and this
    -- is the only way in. Its parts are radiator, axle, brakes, clutch and fuel - checked
    -- against an installed copy, not guessed.
    --
    -- Set to nil if your mechanic script publishes state bags only.
    partsCallback = {
        resource = 'qb-mechanicjob',
        name = 'qb-mechanicjob:server:getVehicleStatus',
    },

    -- Below this percentage a part's warning lamp lights.
    partWarning = 50,

    -- Answer the qb-hud events so that every stock qb resource keeps working with this HUD
    -- installed and qb-hud stopped. Turn off only if you still run qb-hud alongside, which
    -- is not a supported configuration.
    qbHudEvents = true,

    -- Publish the `hud:server:getMenu` callback qb-hud owned, so a third-party resource that
    -- asks for it gets an answer instead of a timeout.
    qbHudCallback = true,
}

-- =======================================================================================
-- 10a-ter. Cluster thresholds
-- =======================================================================================

-- When the speedometer's warning lamps come on. Separate from Config.Alerts, which is about
-- SOUNDS; these are purely what lights up.
Config.Cluster = {
    -- The low-fuel lamp, as a percentage of the tank. 25 is roughly where a real reserve light
    -- comes on. Raise it if your server's fuel drain is fast, lower it if players complain the
    -- lamp is on half the time.
    lowFuel = 25,

    -- Below this, the lamp blinks instead of sitting steady: you are not low, you are about to
    -- stop.
    lowFuelCritical = 8,

    -- Engine health below this lights the engine lamp red.
    engineFault = 25,
}

-- =======================================================================================
-- 10a-bis. Driving warnings
-- =======================================================================================

-- The two chimes a real car has. Both only sound above a speed, because a warning that goes
-- off while you are parked and loading the boot is a warning players turn off.
--
-- These use the game's own frontend sounds rather than a streamed audio file: nothing to
-- download, and they already sit at the right volume against the rest of the game.
--
-- Set `enabled = false` on either to remove it. A player who has turned HUD sounds off in the
-- settings menu hears neither, so this is the operator's ceiling, not an override.
Config.Alerts = {
    -- Above this speed, in the player's own unit, a warning may sound. Below it, silence.
    speed = 40,

    -- Do not start chiming the instant a door is nudged or the belt is unclipped at a light:
    -- the condition has to hold for this long first, in milliseconds.
    grace = 1200,

    seatbelt = {
        enabled = true,
        -- Milliseconds between repeats while the condition holds. 0 means once per occurrence.
        interval = 2500,
        -- A frontend sound: the name, then the sound SET it belongs to.
        sound = 'Beep_Red',
        set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',

        -- Warn PASSENGERS too, not only the driver.
        --
        -- On by default because a passenger can buckle - qb-smallresources' toggle has no
        -- driver check - and the ejection logic throws unbelted passengers through the
        -- windscreen exactly like the driver. It is a warning they can act on.
        --
        -- The belt TELL-TALE is always shown to passengers regardless of this; the switch is
        -- only about the sound. The door chime stays the driver's either way: a passenger
        -- cannot pull over.
        passengers = true,
    },

    -- OFF, and it should stay off on most servers.
    --
    -- A door that reads as open is very often a door that is BROKEN - shot off, torn away in a
    -- crash, or detached by a damage script - and there is nothing the player can do about it.
    -- A chime you cannot silence by driving properly is a chime that trains people to ignore
    -- every other warning. The tell-tale on the cluster still lights, which is the right amount
    -- of information for a fault you cannot fix at the roadside.
    door = {
        enabled = false,
        interval = 4000,
        -- Deliberately a DIFFERENT sound from the belt: two warnings that sound alike are one
        -- warning nobody can act on.
        sound = 'CHECKPOINT_MISSED',
        set = 'HUD_MINI_GAME_SOUNDSET',
    },

    -- The bonnet and boot count as "a door is open" for the chime. Off by default: a mechanic
    -- script leaves the bonnet up while it works, and that is not a driving fault.
    includeBootAndBonnet = false,

    -- A stomach growl when the player is running out of food or water.
    --
    -- It fires on the way DOWN through each threshold and only once per crossing: sitting at
    -- 4% is silent, and eating back up to 60% and starving again growls afresh. A warning that
    -- repeats while you are already looking for a shop is a warning players mute.
    --
    -- The sound is synthesised by the NUI page rather than streamed, so there is no audio file
    -- to ship and `seconds` is an exact cap rather than whatever length a file happens to be.
    -- If your CEF blocks page audio, set `useGameSound` and a frontend sound is used instead -
    -- it will not sound like a stomach, but it will definitely play.
    growl = {
        enabled = true,

        -- Percentages of hunger/thirst REMAINING. Order does not matter; they are sorted.
        thresholds = { 10, 5, 0 },

        -- How far back above a threshold the value has to climb before that threshold can
        -- fire again. Stops a value hovering on the line from growling every tick.
        rearm = 3,

        -- Total length of the growl, in seconds. Capped at 10 by the page.
        seconds = 3.0,

        -- Quiet on purpose. This is a body noise, not an alarm: it should sit under the engine
        -- and the radio and be something you notice, not something that interrupts you.
        volume = 0.22,

        -- Hunger and thirst can both cross at once. This is the gap enforced between any two
        -- growls, in milliseconds, so that is one sound and not two on top of each other.
        cooldown = 8000,

        -- Fall back to a frontend sound instead of the synthesised one.
        useGameSound = false,
        sound = 'Beep_Red',
        set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
    },
}

-- =======================================================================================
-- 10b. When the HUD gets out of the way
-- =======================================================================================

--[[
    A HUD drawn over somebody's phone is in the way. A HUD that vanishes because a radial menu
    drew a small wheel around the crosshair is broken. This section is where you draw that line,
    and it is worth five minutes because every server has a different set of menus.

    ---------------------------------------------------------------------------------------
    WHY THIS NEEDS CONFIGURING AT ALL
    ---------------------------------------------------------------------------------------

    When a resource opens a menu it calls `SetNuiFocus(true, true)`. The HUD can see that
    SOMETHING took focus - but FiveM has no native that says WHICH resource has it. A phone
    covering the whole screen and a target eye drawing a dot look identical from here.

    So a resource has to be identified some other way, and there are three:

        export      the resource publishes a boolean, e.g. exports['v-phone']:IsOpen()
        events      it fires one event when it opens and another when it closes
        stateBag    it sets a flag on LocalPlayer.state

    Anything that offers none of the three falls to the catch-all rule, `onFocus`.

    ---------------------------------------------------------------------------------------
    THE ORDER THINGS ARE DECIDED IN
    ---------------------------------------------------------------------------------------

        1. The game's own screens              -> always hide      (pauseMenu, frontend)
        2. A listed resource with when='show'  -> always STAY UP   (wins over everything below)
        3. A listed resource with when='hide'  -> hide
        4. Focus held by something unlisted    -> whatever `onFocus` says

    A specific answer always beats a general one. That is what lets you say "hide for
    everything, except the radial menu".

    ---------------------------------------------------------------------------------------
    THE THREE THINGS PEOPLE ACTUALLY WANT
    ---------------------------------------------------------------------------------------

    "Hide the HUD for absolutely every menu, no exceptions."
        onFocus = 'hide'   and remove the `when = 'show'` entries below.

    "Never hide the HUD for anything except the pause menu, like qb-hud does."
        onFocus = 'show'   and set every entry below to `when = 'show'`, or empty the list.

    "Hide for the big ones, keep it up for the small ones."   <- how it ships
        onFocus = 'hide'   and mark the small ones `when = 'show'`.
]]
Config.HideWhen = {
    -- ---------------------------------------------------------------------------------
    -- The game's own screens
    -- ---------------------------------------------------------------------------------

    -- The GTA pause menu, the map screen and the loading screen. There is no reading of
    -- "keep my speedometer over the pause menu" that is correct, so leave this on.
    pauseMenu = true,

    -- The game's other full-screen prompts, which the pause menu check does NOT cover because
    -- the pause menu is already closed behind them: the "do you really want to quit" box on
    -- Alt+F4, and the character switch fly-over.
    frontend = true,

    -- ---------------------------------------------------------------------------------
    -- The catch-all rule
    -- ---------------------------------------------------------------------------------

    -- What to do when SOMETHING has NUI focus and it is not one of the resources listed
    -- below - a menu on your server that nobody has told the HUD about.
    --
    --   'auto'   DEFAULT, and it needs no setup. Ask the game whether the thing holding focus
    --            also kept GAME INPUT alive:
    --
    --              input kept  -> the player can still walk, drive and shoot under it, so it
    --                             is an overlay, not a screen. The HUD stays.
    --              input taken -> you cannot play under it, so it is a screen. The HUD hides.
    --
    --            That one question sorts a target eye and a walk-while-open radial menu (both
    --            call SetNuiFocusKeepInput) from a phone or an inventory (which do not),
    --            without either resource having to publish anything. It is why the HUD no
    --            longer disappears for a radial menu on a server nobody has configured.
    --
    --   'hide'   step aside for ANY focus. The old behaviour. Safest, and the most annoying:
    --            a small menu blanks the HUD until you list it below.
    --
    --   'show'   never hide on focus alone. The HUD then only ever hides for the game's own
    --            screens and for the resources listed below. Closest to how qb-hud behaves.
    onFocus = 'auto',

    -- ---------------------------------------------------------------------------------
    -- Per resource
    -- ---------------------------------------------------------------------------------

    --[[
        One entry per menu you care about. Fields:

          resource    the folder name, exactly as it appears in resources/
          when        'hide' (default) or 'show'
          hides       optional, and only meaningful with when='hide'. Narrows WHAT goes away:
                          hides = { hud = true, minimap = false }
                      keeps the minimap up while the gauges and the speedometer step aside.
                      Absent means everything hides.

        And ONE of these, to detect it:

          export      = 'IsOpen'                  a boolean export the resource publishes
          export      = { 'IsOpen', 'isOpen' }    several candidates; the first that answers
                                                  wins. Inventories all publish this and none
                                                  of them agree on the name, so guessing a few
                                                  is cheaper than grepping.
          openEvent   = '...'                     fired when it opens
          closeEvent  = '...'                     fired when it closes   (use both together)
          stateBag    = 'inv_busy'                a boolean on LocalPlayer.state

        A resource that is not started, or whose export does not exist on your build, is
        skipped silently - a wrong entry here can never break anything, it just does nothing.

        YOU PROBABLY DO NOT NEED TO ADD ANYTHING. With `onFocus = 'auto'` above, a menu that
        takes focus is handled correctly without being listed. This list is for the two cases
        auto cannot see:

          * a resource that covers the screen WITHOUT taking NUI focus (rare, but some phones
            keep the controls live so you can walk while texting)
          * a resource that takes focus and input in a way that gets auto's answer wrong

        TO ADD ONE: grep the resource folder for `exports(` and look for an open/closed
        boolean. If it publishes none, grep for `TriggerEvent(` near where it opens and closes
        and use the event pair.
    ]]
    resources = {
        -- Phones and inventories: these cover the screen, so they hide everything.
        --
        -- Several export names per resource because forks rename them, and a name that does
        -- not exist costs one failed call, once, and is then never tried again.
        { resource = 'v-phone',      export = { 'IsOpen', 'isOpen' } },
        { resource = 'qb-phone',     export = { 'IsOpen', 'isOpen' } },
        { resource = 'lb-phone',     export = { 'IsOpen', 'isOpen' } },
        { resource = 'gksphone',     export = { 'IsOpen', 'isOpen' } },
        { resource = 'qb-inventory', export = { 'IsInventoryOpen', 'isInventoryOpen' } },
        { resource = 'ox_inventory', export = { 'getInventoryOpen', 'inventoryOpen' } },
        { resource = 'qs-inventory', export = { 'inInventory', 'isInventoryOpen', 'IsOpen' },
          stateBag = 'inv_busy' },
        { resource = 'origen_inventory', export = { 'isInventoryOpen', 'IsOpen' } },

        -- The radial menu draws a wheel around the crosshair. `auto` already keeps the HUD up
        -- for it when it runs in walk-while-open mode; this entry makes it explicit for the
        -- mode where it does not, because a wheel is never a reason to blank a speedometer.
        --
        -- It publishes no export, so it is detected by the two events it already fires.
        {
            resource = 'qb-radialmenu',
            when = 'show',
            openEvent = 'qb-radialmenu:client:onRadialmenuOpen',
            closeEvent = 'qb-radialmenu:client:onRadialmenuClose',
        },

        -- Target eyes are handled by `auto` - both qb-target and ox_target call
        -- SetNuiFocusKeepInput, so the HUD already stays up for them and no entry is needed.
        -- If you set onFocus = 'hide' and want them exempted anyway, add:
        --     { resource = 'ox_target', when = 'show', stateBag = 'hasOxTarget' },

        -- An example of the narrowed form. Uncommented, this would let a context menu take the
        -- gauges away while leaving the map on screen.
        -- {
        --     resource = 'qb-menu',
        --     when = 'hide',
        --     hides = { hud = true, minimap = false },
        --     openEvent = 'qb-menu:client:openMenu',
        --     closeEvent = 'qb-menu:client:closeMenu',
        -- },
    },

    -- ---------------------------------------------------------------------------------
    -- Timing
    -- ---------------------------------------------------------------------------------

    -- How long the HUD stays hidden after the thing that hid it went away, in milliseconds.
    -- A short tail stops the HUD flashing back for one frame between two menus that open one
    -- after the other. Set to 0 if you want it back instantly.
    linger = 250,
}

-- =======================================================================================
-- 11b. Odometer
-- =======================================================================================

-- The total distance a vehicle has covered, shown on the speedometer.
--
-- GTA does not track this: there is no native that answers "how far has this car been
-- driven". So it is measured here - the client adds up the distance it travels while it is
-- the driver, and the server stores the total per number plate in its own table.
--
-- If a resource that already keeps a mileage is installed, it is read instead: better one
-- number than two that disagree. jim-mechanic keeps one per vehicle.
Config.Odometer = {
    enabled = true,

    -- Where to read a mileage from before falling back to this resource's own counter. Each
    -- entry is a vehicle STATE BAG name, checked in order; the first number found wins.
    providers = { 'odometer', 'mileage', 'jimOdo' },

    -- Track it here when no provider answered. Off means the readout only appears on servers
    -- that already have a mileage resource.
    track = true,
    table = 'vhud_odometer',

    -- Metres travelled between saves. Lower is more accurate across a crash, higher is fewer
    -- writes; 1000 is a database row per kilometre per driver.
    saveEvery = 1000,

    -- Show the total in kilometres or miles. 'units' follows the player's speed setting.
    unit = 'units',            -- 'units' | 'km' | 'mi'

    -- Round the display to this many decimals. A trip counter wants one; a total wants none.
    decimals = 0,
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
        odometer = true,         -- total distance, see Config.Odometer
        parts = true,            -- wear lamps from the mechanic script, see Config.Compat.parts
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
