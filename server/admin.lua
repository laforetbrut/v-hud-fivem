--[[
    server/admin.lua

    `/hudadmin` - what a staff member can do to somebody else's HUD.

    A push is a PATCH, not a replacement: it moves the keys the preset names and leaves the
    player's positions, colours and element toggles alone. That is deliberate. An admin
    setting the server theme should not cost every player the layout they arranged, and an
    admin who genuinely wants a clean slate has `reset` for exactly that.

    Everything here re-checks the ace on every call. A command registered as restricted is
    still reachable from the console and from a resource, so the check cannot live only in
    the registration.
]]

local function targets(token)
    if token == 'all' or token == '*' then
        return GetPlayers()
    end

    local id = tonumber(token)
    if not id then return {} end
    if GetPlayerName(id) == nil then return {} end

    return { tostring(id) }
end

local function push(src, list, patch, describe)
    if #list == 0 then
        Bridge.notify(src, L('notify.admin_no_target'), 'error')
        return
    end

    for _, target in ipairs(list) do
        TriggerClientEvent('vhud:client:AdminPatch', tonumber(target), patch, describe)
    end

    Bridge.notify(src, L('notify.admin_pushed', #list), 'success')
end

local function usage(src)
    local lines = {
        '/hudadmin theme <theme> <id|all>',
        '/hudadmin preset <name> <id|all>',
        '/hudadmin speedo <style> <id|all>',
        '/hudadmin reset <id|all>',
        '/hudadmin list',
    }

    for _, line in ipairs(lines) do
        if src == 0 then
            print(('[v-hud] %s'):format(line))
        else
            TriggerClientEvent('chat:addMessage', src, { args = { 'v-hud', line } })
        end
    end
end

local function listOptions(src)
    local themes = {}
    for _, theme in ipairs(Themes.list()) do themes[#themes + 1] = theme.key end

    local speedos = {}
    for _, entry in ipairs(Speedometers.list()) do speedos[#speedos + 1] = entry.key end

    local presets = {}
    for key in pairs(Config.Presets or {}) do presets[#presets + 1] = key end
    table.sort(presets)

    local lines = {
        ('themes: %s'):format(table.concat(themes, ', ')),
        ('speedometers: %s'):format(table.concat(speedos, ', ')),
        ('presets: %s'):format(#presets > 0 and table.concat(presets, ', ') or '(none)'),
    }

    for _, line in ipairs(lines) do
        if src == 0 then
            print(('[v-hud] %s'):format(line))
        else
            TriggerClientEvent('chat:addMessage', src, { args = { 'v-hud', line } })
        end
    end
end

local function handle(src, args)
    if not Config.Policy.allowAdminPush then
        Bridge.notify(src, L('notify.no_permission'), 'error')
        return
    end

    if not Bridge.isAdmin(src) then
        Bridge.notify(src, L('notify.no_permission'), 'error')
        return
    end

    local action = args[1] and tostring(args[1]):lower() or ''

    if action == 'list' then
        listOptions(src)
        return
    end

    if action == 'reset' then
        local list = targets(tostring(args[2] or ''))
        if #list == 0 then
            Bridge.notify(src, L('notify.admin_no_target'), 'error')
            return
        end

        for _, target in ipairs(list) do
            local id = tonumber(target)
            local identifier = Bridge.identifier(id)
            if identifier then Storage.clear(identifier) end
            TriggerClientEvent('vhud:client:ApplySettings', id, Settings.default(), true)
        end

        Bridge.notify(src, L('notify.admin_pushed', #list), 'success')
        return
    end

    if action == 'theme' then
        local key = tostring(args[2] or '')
        if not Themes.allowed(key) or key == 'custom' then
            usage(src)
            listOptions(src)
            return
        end

        local theme = Themes[key]
        local patch = HUD.deepCopy(theme.patch)
        patch.theme = key
        push(src, targets(tostring(args[3] or '')), patch,
            Config.Policy.announceAdminPush and L('notify.theme_forced', theme.label) or nil)
        return
    end

    if action == 'speedo' then
        local key = tostring(args[2] or '')
        if not Speedometers.allowed(key) then
            usage(src)
            listOptions(src)
            return
        end

        push(src, targets(tostring(args[3] or '')), { speedometer = { style = key } },
            Config.Policy.announceAdminPush and L('notify.settings_saved') or nil)
        return
    end

    if action == 'preset' then
        local key = tostring(args[2] or '')
        local preset = (Config.Presets or {})[key]
        if not preset then
            usage(src)
            listOptions(src)
            return
        end

        push(src, targets(tostring(args[3] or '')), HUD.deepCopy(preset.patch),
            Config.Policy.announceAdminPush and L('notify.settings_saved') or nil)
        return
    end

    usage(src)
end

CreateThread(function()
    Wait(1200)

    Bridge.addCommand('hudadmin', L('command.hudadmin'), {
        { name = 'action', help = 'theme | preset | speedo | reset | list' },
        { name = 'value', help = L('command.arg_theme') },
        { name = 'target', help = L('command.arg_target') },
    }, true, function(src, args)
        handle(src, args or {})
    end)
end)

-- ---------------------------------------------------------------------------------------
-- Exports for another resource
-- ---------------------------------------------------------------------------------------

--- Push a settings patch to one player. Same rules as the command: a patch, not a
--- replacement, and the server's locked paths still win on the client side.
exports('PushSettings', function(src, patch, message)
    if type(patch) ~= 'table' then return false end
    if not GetPlayerName(src) then return false end

    TriggerClientEvent('vhud:client:AdminPatch', src, patch, message)
    return true
end)

--- Reset one player back to the server defaults, stored copy included.
exports('ResetSettings', function(src)
    if not GetPlayerName(src) then return false end

    local identifier = Bridge.identifier(src)
    if identifier then Storage.clear(identifier) end

    TriggerClientEvent('vhud:client:ApplySettings', src, Settings.default(), true)
    return true
end)
