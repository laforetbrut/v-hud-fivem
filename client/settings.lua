--[[
    client/settings.lua

    `State` is the client's single source of truth: what the server said, what the player
    chose, and what is actually in force once a job override has been laid on top.

    Three tables, and keeping them apart is what makes job overrides work without stealing
    anybody's settings:

        State.player    what the player chose. This is what gets saved.
        State.settings  what is in force = player + job override + server policy.
        State.boot      what the server sent once: themes, statuses, locked paths, strings.

    An override is applied at the point of use and never written back, so quitting the job
    gives the player their own HUD back exactly as it was.
]]

State = {
    ready = false,
    menuOpen = false,
    layoutMode = false,
    -- /hidehud: the whole HUD off until it is typed again. Deliberately NOT a saved setting,
    -- so a relog or a restart always brings the HUD back - a player who forgot they hid it
    -- would otherwise report a broken resource.
    manualHide = false,
    -- Whether THIS resource is currently holding NUI focus. Tracked rather than read back
    -- with IsNuiFocused(), which is global: acting on that native takes the cursor away from
    -- whichever other resource actually owns it.
    focusHeld = false,
    boot = nil,
    player = nil,
    settings = nil,
    roles = { job = '', jobType = '', gang = '' },
}

--- Toggle the whole HUD, minimap included. Returns the new state.
function State.toggleHidden()
    State.manualHide = not State.manualHide
    SendNUIMessage({ action = 'manualHide', on = State.manualHide })
    -- The minimap loop picks the change up on its next pass; doing it here too makes the
    -- command feel instant instead of up to a quarter second late.
    if State.manualHide then DisplayRadar(false) end
    return State.manualHide
end

local KVP_KEY = 'vhud:settings'
local saveTimer = 0
local savePending = false

-- ---------------------------------------------------------------------------------------
-- Local storage
-- ---------------------------------------------------------------------------------------

--- Read the machine-local copy. Returns nil twice over when there is nothing stored or when
--- what is stored no longer parses - both mean "start from the server defaults".
local function readKvp()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw then return nil, 0 end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil, 0 end

    -- v1.0.0 wrote the settings table straight in, with no wrapper. Read both shapes so an
    -- early tester does not lose their layout to a format change.
    if decoded.settings == nil then return decoded, 0 end

    return decoded.settings, tonumber(decoded.timestamp) or 0
end

--- Seconds since the epoch, on the CLIENT.
---
--- `os.time` does not exist in the client runtime - only on the server - and calling it is an
--- immediate "attempt to index a nil value (global 'os')" that takes the whole save path with
--- it. GetCloudTimeAsInt is the client's UNIX clock and is directly comparable with the
--- server's os.time, which is the whole point: the two timestamps decide which stored copy of
--- the settings is newer.
local function now()
    local ok, seconds = pcall(GetCloudTimeAsInt)
    if ok and type(seconds) == 'number' and seconds > 0 then return seconds end
    return 0
end

local function writeKvp(settings)
    if not Config.Persistence.kvp then return end

    SetResourceKvp(KVP_KEY, json.encode({
        settings = settings,
        timestamp = now(),
    }))
end

-- ---------------------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------------------

--- Recompute State.settings from State.player plus whatever override the current job earns,
--- then push the result to the NUI and to the native-side consumers.
function State.apply(announce)
    if not State.player then return end

    State.settings = Settings.withJobOverride(
        HUD.deepCopy(State.player),
        State.roles.job,
        State.roles.jobType,
        State.roles.gang
    )

    SendNUIMessage({
        action = 'settings',
        settings = State.settings,
        locked = State.boot and State.boot.locked or {},
    })

    -- The minimap and the cinematic bars are native, not NUI, so they are told separately.
    if Minimap then Minimap.apply(State.settings) end
    if Cinematic then Cinematic.apply(State.settings.cinematic) end

    if announce then
        Compat.notify(L('notify.settings_loaded'), 'success')
    end
end

--- Replace the player's settings wholesale. `announce` shows the toast; `save` writes it.
function State.set(settings, announce, save)
    State.player = Settings.normalise(settings)
    State.apply(announce)

    if save ~= false then State.queueSave() end
end

--- Change one dotted path. This is what every switch, slider and colour well in the menu
--- calls, one change at a time, so a live preview costs one merge rather than a full
--- re-validation of the whole tree.
function State.setPath(path, value)
    if not State.player then return false end
    if Settings.isLocked(path) then
        Compat.notify(L('notify.setting_locked'), 'error')
        return false
    end

    local draft = HUD.deepCopy(State.player)
    if not Settings.setPath(draft, path, value) then return false end

    -- Touching anything a theme owns takes the player off that theme. Without this the menu
    -- would keep claiming "Miami" while showing colours Miami never had.
    if path ~= 'theme' and State.ownedByTheme(path) then
        draft.theme = 'custom'
    end

    State.player = Settings.normalise(draft)
    State.apply(false)
    State.queueSave()
    return true
end

-- Paths a theme sets. Changing one of these is what turns the theme into 'custom'.
local THEME_OWNED = { 'style.', 'colours.', 'minimap.shape', 'minimap.borders', 'speedometer.style', 'compass.style' }

--- Whether `path` is something a theme would have set.
function State.ownedByTheme(path)
    for _, prefix in ipairs(THEME_OWNED) do
        if path == prefix or path:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Apply a named theme over the player's settings, keeping positions and element toggles.
function State.applyTheme(key)
    if not Themes.allowed(key) or key == 'custom' then return false end
    if Settings.isLocked('theme') then
        Compat.notify(L('notify.setting_locked'), 'error')
        return false
    end

    State.player = Settings.normalise(Themes.apply(HUD.deepCopy(State.player), key))
    State.apply(false)
    State.queueSave()
    return true
end

-- ---------------------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------------------

--- Mark the settings dirty. The write happens on the debounce timer below, because dragging
--- a colour slider fires a change per frame and each one would otherwise be a KVP write and
--- a server round trip.
function State.queueSave()
    savePending = true
    saveTimer = GetGameTimer() + Config.Persistence.debounce
end

--- Write now, skipping the debounce. Used when the menu closes and when the resource stops.
function State.flushSave()
    if not savePending or not State.player then return end
    savePending = false

    writeKvp(State.player)
    TriggerServerEvent('vhud:server:SaveSettings', { settings = State.player })
end

CreateThread(function()
    while true do
        Wait(250)
        if savePending and GetGameTimer() >= saveTimer then
            State.flushSave()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    State.flushSave()

    -- Give the cursor back before the resource goes away. A stop with focus held leaves the
    -- player pointing at nothing, with the code that would have released it now unloaded.
    if State.focusHeld then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SetPlayerControl(PlayerId(), true, 0)
    end
end)

-- ---------------------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------------------

local booted = false

local function requestBoot()
    local settings, timestamp = readKvp()
    TriggerServerEvent('vhud:server:RequestBoot', {
        settings = settings,
        timestamp = timestamp,
    })
end

RegisterNetEvent('vhud:client:Boot', function(payload)
    if type(payload) ~= 'table' then return end

    State.boot = payload.static
    State.roles = payload.roles or State.roles
    State.player = Settings.normalise(payload.settings)

    -- The NUI needs the static half before it can render anything: it draws the status
    -- gauges from Config.Status and the menu from the theme and speedometer lists.
    SendNUIMessage({
        action = 'boot',
        static = State.boot,
        settings = State.player,
    })

    State.apply(false)

    -- Seed the values the server already knows so the gauges are right on the first frame
    -- rather than after the first metadata event.
    if Needs then Needs.seed(payload.hunger, payload.thirst, payload.stress) end

    State.ready = true
    booted = true
    HUD.debug('booted')
end)

RegisterNetEvent('vhud:client:ApplySettings', function(settings, announce)
    State.set(settings, announce == true, true)
end)

--- An admin push. A patch over what the player has, never a replacement, and it goes through
--- the same normalisation as anything else so a locked path still wins.
RegisterNetEvent('vhud:client:AdminPatch', function(patch, message)
    if type(patch) ~= 'table' or not State.player then return end

    State.player = Settings.normalise(HUD.merge(State.player, patch))
    State.apply(false)
    State.queueSave()

    if message then Compat.notify(message, 'primary', true) end
end)

RegisterNetEvent('vhud:client:Toast', function(message, kind)
    SendNUIMessage({ action = 'toast', message = message, kind = kind })
end)

--- Job or gang changed: recompute the override without touching what the player chose.
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    State.roles.job = (job and job.name) or ''
    State.roles.jobType = (job and job.type) or ''
    State.apply(false)
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    State.roles.gang = (gang and gang.name) or ''
    State.apply(false)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(500)
    requestBoot()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    -- A character switch is a hard reset. Anything left open here would hold focus into the
    -- multicharacter screen, which is the one place a stuck cursor cannot be escaped.
    State.closeMenu()
    State.ready = false
    State.manualHide = false
    SendNUIMessage({ action = 'hide' })
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    CreateThread(function()
        -- A restart mid-session has to re-boot itself: OnPlayerLoaded already fired and is
        -- not coming again. Waiting for the login state rather than a fixed delay is what
        -- makes this work on a slow machine as well as a fast one.
        local deadline = GetGameTimer() + 30000
        while not booted and GetGameTimer() < deadline do
            if LocalPlayer.state.isLoggedIn then
                requestBoot()
                Wait(3000)
            else
                Wait(500)
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------------------

--- Every callback in this resource goes through here so that one always answers. A NUI
--- callback that never calls `cb` leaves the page waiting forever, and the symptom - a menu
--- that stops responding after one specific click - is miserable to track down.
local function callback(name, handler)
    RegisterNUICallback(name, function(data, cb)
        local ok, err = pcall(handler, type(data) == 'table' and data or {})
        if not ok then HUD.debug('nui callback failed:', name, err) end
        cb('ok')
    end)
end

callback('close', function()
    State.closeMenu()
end)

-- The page loaded, but not all of it. See the note beside checkModules() in html/js/app.js:
-- CEF caches index.html by URL and does not drop it on a resource restart, so a change to the
-- script list there can be invisible until the game client itself is restarted. Printed rather
-- than debug-logged, because the whole point is that this failure is otherwise silent.
callback('stalePage', function(data)
    local missing = type(data.missing) == 'table' and table.concat(data.missing, ', ') or '?'

    HUD.warn(('The HUD page is running an OLD copy of html/index.html - these modules did not ' ..
        'load: %s. FiveM caches NUI pages by URL and does not drop them on `restart`. ' ..
        'Restart the GAME CLIENT once and it will pick up the new page. Stylesheets and ' ..
        'scripts do not need this; only index.html itself.'):format(missing))
end)

callback('setPath', function(data)
    if type(data.path) ~= 'string' then return end
    State.setPath(data.path, data.value)
end)

callback('setPaths', function(data)
    -- A batch, for the colour picker: changing an accent recolours several keys at once and
    -- one save is better than six.
    if type(data.changes) ~= 'table' then return end

    local draft = HUD.deepCopy(State.player)
    local touched = false

    for path, value in pairs(data.changes) do
        if type(path) == 'string' and not Settings.isLocked(path) then
            if Settings.setPath(draft, path, value) then
                touched = true
                if State.ownedByTheme(path) then draft.theme = 'custom' end
            end
        end
    end

    if not touched then return end

    State.player = Settings.normalise(draft)
    State.apply(false)
    State.queueSave()
end)

callback('applyTheme', function(data)
    State.applyTheme(data.theme)
end)

callback('applyLayout', function(data)
    if type(data.layout) ~= 'string' then return end
    if Settings.isLocked('positions') then
        Compat.notify(L('notify.setting_locked'), 'error')
        return
    end

    State.player = Settings.applyLayout(State.player, data.layout)
    State.apply(false)
    State.queueSave()
end)

callback('applyPreset', function(data)
    local preset = data.preset
    if type(preset) ~= 'table' then return end

    State.player = Settings.normalise(HUD.merge(State.player, preset))
    State.apply(false)
    State.queueSave()
end)

callback('reset', function()
    TriggerServerEvent('vhud:server:ResetSettings')
    State.set(Settings.default(), true, true)
end)

callback('resetSection', function(data)
    local section = data.section
    if type(section) ~= 'string' then return end

    local defaults = Settings.default()
    local branch = Settings.getPath(defaults, section)
    if branch == nil then return end

    local draft = HUD.deepCopy(State.player)
    if not Settings.setPath(draft, section, HUD.deepCopy(branch)) then return end

    State.player = Settings.normalise(draft)
    State.apply(false)
    State.queueSave()
end)

callback('layoutMode', function(data)
    local wanted = data.on == true

    -- Idempotent. The page posts this from more than one place - the Done button, the close
    -- handler, the escape key - and firing the toast on every one of them is what filled the
    -- screen with "Disposition enregistrée".
    if wanted == State.layoutMode then return end
    State.layoutMode = wanted

    -- Opening the editor from the menu closes the menu, and the page does that ITSELF without
    -- posting `close` - so without this line the Lua side still believed the menu was open,
    -- SetNuiFocus below kept focus held for a menu that was no longer on screen, and the
    -- player was stuck with a cursor and no way to dismiss anything. Clicking Done released
    -- nothing, because `false or true` is still true.
    if State.layoutMode then State.menuOpen = false end

    local wantsFocus = State.layoutMode or State.menuOpen
    State.focusHeld = wantsFocus
    SetNuiFocus(wantsFocus, wantsFocus)
    if Config.Menu.freezeWhileOpen then
        SetPlayerControl(PlayerId(), not wantsFocus, 0)
    end

    Compat.notify(State.layoutMode and L('notify.layout_edit_on') or L('notify.layout_edit_off'),
        State.layoutMode and 'primary' or 'success')

    if not State.layoutMode then State.flushSave() end
end)

callback('sound', function(data)
    Compat.playSound(data.name or 'click', tonumber(data.volume) or 0.08)
end)

callback('import', function(data)
    if Config.Policy.allowSharing == false then
        Compat.notify(L('notify.setting_locked'), 'error')
        return
    end

    -- The page has already decoded the share code; what arrives here is an untrusted table
    -- like any other. State.set runs it through the full pipeline - merged into the schema so
    -- unknown keys are dropped, every value coerced, then policed - so a code exported on a
    -- server with different rules cannot carry a locked value onto this one.
    local incoming = data.settings
    if type(incoming) ~= 'table' then
        -- v1.0.0 posted a JSON string. Read both shapes so an old code still imports.
        if type(data.payload) == 'string' then
            local ok, decoded = pcall(json.decode, data.payload)
            incoming = (ok and type(decoded) == 'table') and decoded or nil
        end
    end

    if type(incoming) ~= 'table' then
        Compat.notify(L('advanced.import_bad'), 'error')
        return
    end

    -- Positions are the player's own arrangement of their own screen. An imported look should
    -- not pick their HUD up and move it, so the layout they built is kept.
    if Config.Policy.importKeepsLayout ~= false and State.player then
        incoming.positions = HUD.deepCopy(State.player.positions)
    end

    State.set(incoming, false, true)
    Compat.notify(L('advanced.import_ok'), 'success')
end)

-- ---------------------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------------------

function State.openMenu()
    if State.menuOpen or State.layoutMode then return end

    -- Not ready means the boot payload has not arrived: the page has no themes, no strings
    -- and no settings, so the menu would open empty AND hold focus.
    --
    -- The explanation is only worth showing to somebody already in the world. On the
    -- multicharacter screen the key is being pressed at a HUD that is not supposed to exist
    -- yet, and a toast over the character list is noise.
    if not State.ready then
        if LocalPlayer.state.isLoggedIn then
            Compat.notify(L('notify.hud_not_ready'), 'error', true)
        end
        return
    end

    -- Another resource holding focus means a menu, the phone or the character screen is up.
    -- Taking focus on top of it leaves two pages fighting for the cursor and the other one
    -- unable to give it back.
    if IsNuiFocused() then return end

    State.menuOpen = true
    State.focusHeld = true
    SetNuiFocus(true, true)
    if Config.Menu.freezeWhileOpen then
        SetPlayerControl(PlayerId(), false, 0)
    end

    SendNUIMessage({
        action = 'openMenu',
        settings = State.player,
        locked = State.boot and State.boot.locked or {},
        providers = Compat.report(),
    })

    Compat.playSound('click', 0.1)
end

function State.closeMenu()
    -- Deliberately NOT guarded on "is something open". This is the function that gives the
    -- player their mouse back, so it has to work even when the two flags disagree with what
    -- is actually on screen - which is exactly the situation it is needed in.
    local wasOpen = State.menuOpen or State.layoutMode

    State.menuOpen = false
    State.layoutMode = false

    -- Only drop focus if it was OURS. Another resource may have taken it since - the
    -- multicharacter screen, the phone - and releasing it on their behalf strands them
    -- instead.
    if State.focusHeld then
        State.focusHeld = false
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if Config.Menu.freezeWhileOpen then
            SetPlayerControl(PlayerId(), true, 0)
        end
    end

    SendNUIMessage({ action = 'closeMenu' })
    State.flushSave()
    if wasOpen then Compat.playSound('click', 0.1) end
end

-- ---------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------

--- The settings in force. A copy: a caller that mutated the live table would desynchronise
--- the HUD from what is saved.
exports('GetSettings', function()
    return State.settings and HUD.deepCopy(State.settings) or nil
end)

--- Patch the player's settings from another resource. Same rules as an admin push.
exports('SetSettings', function(patch)
    if type(patch) ~= 'table' or not State.player then return false end

    State.player = Settings.normalise(HUD.merge(State.player, patch))
    State.apply(false)
    State.queueSave()
    return true
end)

--- Register a theme from another resource. See THEMES.md.
--- The key still has to be in Config.Policy.themes: what is OFFERED is the server owner's
--- decision, not the theme author's.
exports('RegisterTheme', function(key, definition)
    return Themes.register(key, definition)
end)

--- The themes this server currently offers, for a resource that wants to list them.
exports('GetThemes', function() return Themes.list() end)

exports('OpenMenu', function() State.openMenu() end)
exports('CloseMenu', function() State.closeMenu() end)
exports('IsMenuOpen', function() return State.menuOpen end)
