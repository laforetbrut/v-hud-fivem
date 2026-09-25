fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-hud'
author 'vyrriox'
description 'A fully player-configurable HUD for qb-core, qbx_core, ESX and ox_core: movable elements, seven themes, ten speedometers, twenty-one dashboard tell-tales, compass, street names, compact and immersive modes.'
version '1.0.1'

-- No hard dependency on purpose. qb-core, oxmysql, qb-fuel, LegacyFuel, ps-fuel, cdn-fuel,
-- pma-voice, saltychat and interact-sound are ALL detected at runtime and all optional.
-- See config.lua -> Config.Compat and bridge/client/compat.lua.

shared_scripts {
    -- The bridge first: it defines HUD, the locale helper and the settings schema the rest
    -- of the resource is written against.
    'bridge/shared/hud.lua',
    'bridge/shared/locale.lua',

    -- English first: it is the fallback for any key missing from another locale file, so it
    -- is the base table the others are read against.
    'locales/en.lua',
    'locales/fr.lua',

    'config.lua',

    -- Themes and speedometers read Config, so they load after it. They are shared because the
    -- server validates a saved theme name against the same table the client offers.
    'shared/themes.lua',
    'shared/speedometers.lua',

    -- Drop-in themes. One file per theme, each defining `Themes.<key>`; see THEMES.md.
    --
    -- Listed by name rather than globbed with `themes/*.lua`, and that is deliberate. A glob
    -- that matches nothing prints a warning on every restart, and a glob does not resolve at
    -- all when the resource is installed as a junction to a git checkout - which is how
    -- anybody developing against it runs it. One line per theme is the cost.
    'themes/example.lua',
    -- Merge/validate a settings payload. Shared because the client applies it and the server
    -- re-validates it: one implementation, no drift.
    'shared/settings.lua',
}

client_scripts {
    -- Runtime detection of everything optional. FIRST, because every client file below asks
    -- it what is installed.
    'bridge/client/compat.lua',
    'client/settings.lua',
    'client/minimap.lua',
    'client/compass.lua',
    'client/vehicle.lua',
    -- Before client/vehicle.lua would be wrong: the odometer is read BY the vehicle reader,
    -- but only at runtime, and this file's own loop needs State from client/settings.lua.
    'client/odometer.lua',
    'client/stress.lua',
    'client/main.lua',
    'client/commands.lua',
}

server_scripts {
    'bridge/server/framework.lua',
    'server/storage.lua',
    'server/main.lua',
    'server/stress.lua',
    'server/odometer.lua',
    'server/admin.lua',
}

ui_page 'html/index.html'

-- The minimap shape masks and the cleaned-up minimap graphics. FiveM picks a folder named
-- `stream/` up automatically, so there is nothing to list; this comment is here because a
-- missing stream folder produces a subtle bug rather than an error - the game keeps its
-- rounded map while the HUD draws a square border around it, and the two do not line up.
--
-- squaremap.ytd / circlemap.ytd are the radar masks AddReplaceTexture swaps in.
-- minimap.ytd / minimap.gfx remove the vanilla frame and its baked-in health bars.
-- All four originate from the QBCore qb-hud resource and are the community-standard set.

files {
    'html/index.html',
    'html/css/reset.css',
    'html/css/hud.css',
    'html/css/status.css',
    'html/css/speedo.css',
    'html/css/menu.css',
    'html/css/themes.css',
    'html/js/util.js',
    'html/js/state.js',
    'html/js/status.js',
    'html/js/speedo.js',
    'html/js/compass.js',
    'html/js/toast.js',
    'html/js/sound.js',
    'html/js/layout.js',
    'html/js/menu.js',
    'html/js/app.js',
}
