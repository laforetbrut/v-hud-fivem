--[[
    client/commands.lua

    Commands and the key mapping.

    The key goes through RegisterKeyMapping rather than a control check in a loop, so the
    player can rebind it in the GTA settings under FiveM > Key bindings and so it costs
    nothing while it is not pressed.
]]

RegisterCommand('vhud:open', function()
    -- The key is also the way out of the layout editor, so it closes whichever surface is up.
    if State.menuOpen or State.layoutMode then
        State.closeMenu()
    else
        State.openMenu()
    end
end, false)

--- The escape hatch. If anything ever leaves a cursor on screen with nothing behind it, this
--- takes the game back without a relog. Registered separately from the menu key so it still
--- works when the menu key is what got stuck.
RegisterCommand('hudunstuck', function()
    State.closeMenu()
    Compat.notify(L('notify.settings_loaded'), 'success', true)
end, false)

if Config.Menu.key and Config.Menu.key ~= '' then
    RegisterKeyMapping('vhud:open', L('command.menu'), 'keyboard', Config.Menu.key)
end

if Config.Menu.command and Config.Menu.command ~= '' then
    RegisterCommand(Config.Menu.command, function()
        State.openMenu()
    end, false)
end

-- `/menu` is what qb-hud used. Registered only when qb-hud is not running, because two
-- resources owning one command name is a coin toss over which one answers.
if Config.Menu.legacyCommand and Config.Menu.legacyCommand ~= '' then
    CreateThread(function()
        Wait(1000)
        local state = GetResourceState('qb-hud')
        if state == 'started' or state == 'starting' then return end

        RegisterCommand(Config.Menu.legacyCommand, function()
            State.openMenu()
        end, false)
    end)
end

if Config.Cinematic.command and Config.Cinematic.command ~= '' then
    RegisterCommand(Config.Cinematic.command, function()
        Cinematic.toggle()
    end, false)
end

if Config.Menu.hideCommand and Config.Menu.hideCommand ~= '' then
    RegisterCommand(Config.Menu.hideCommand, function()
        local hidden = State.toggleHidden()
        -- Forced through even with notifications off: a player who hid their HUD and their
        -- notifications needs the one message telling them how to get it back.
        Compat.notify(hidden and L('notify.hud_hidden') or L('notify.hud_shown'), 'primary', true)
    end, false)
end

RegisterCommand('hudreset', function()
    if not State.ready then return end
    TriggerServerEvent('vhud:server:ResetSettings')
    State.set(Settings.default(), true, true)
end, false)

--- What was detected, printed to F8. The first thing to ask for when somebody reports that a
--- gauge is stuck: it names the fuel script, the voice script and the inventory actually in
--- use, which is usually the whole answer.
RegisterCommand('hudinfo', function()
    local report = Compat.report()
    local version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0'

    print(('[v-hud] version %s'):format(version))
    print(('[v-hud] framework : %s'):format(report.framework))
    print(('[v-hud] fuel      : %s'):format(report.fuel))
    print(('[v-hud] voice     : %s'):format(report.voice))
    print(('[v-hud] notify    : %s'):format(report.notify))
    print(('[v-hud] sounds    : %s'):format(report.sounds))
    print(('[v-hud] inventory : %s'):format(report.inventory))
    print(('[v-hud] language  : %s'):format(CurrentLocale()))
    print(('[v-hud] theme     : %s'):format(State.player and State.player.theme or 'not loaded'))

    Compat.notify(('v-hud: %s / %s'):format(report.framework, report.fuel), 'primary', true)
end, false)

-- Escape closes the menu. NUI focus swallows the key, so the page reports it back through the
-- close callback; this is only the native-side fallback for a page that stopped answering.
--
-- The second half is the safety net. NUI focus is the one state that can strand a player: a
-- cursor on screen, no menu to dismiss, and no keybind that works.
--
-- It is keyed on OUR OWN flag, never on IsNuiFocused(). That native is global - it is true
-- whenever ANY resource holds focus - so a watchdog built on it tears the focus away from
-- the multicharacter screen, the phone and the inventory every time it runs. It did exactly
-- that: qb-multicharacter lost its cursor twice a second and the HUD announced "layout
-- saved" each time.
CreateThread(function()
    -- The watchdog needs the fault to PERSIST before it acts. Its check runs after a Wait,
    -- and the world moves during a Wait: opening the menu one tick into that pause made the
    -- stale "nothing is open" reading true and the fresh "we hold focus" reading true at the
    -- same moment, so the watchdog closed the menu the instant it was opened. Requiring two
    -- consecutive confirmations removes every such race, at the cost of a second of delay in
    -- the case that actually needs it.
    local strikes = 0

    while true do
        if State.menuOpen or State.layoutMode then
            strikes = 0
            Wait(0)
            if Config.Menu.closeOnEscape and IsControlJustReleased(0, 322) then
                State.closeMenu()
            end
        else
            Wait(500)

            -- Re-read EVERYTHING after the wait. The condition that sent this thread down
            -- the else branch is half a second old and may no longer be true.
            if State.focusHeld and not State.menuOpen and not State.layoutMode then
                strikes = strikes + 1
                if strikes >= 2 then
                    strikes = 0
                    HUD.debug('releasing focus this resource took and did not give back')
                    State.closeMenu()
                end
            else
                strikes = 0
            end
        end
    end
end)
