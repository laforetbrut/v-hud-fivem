"""
tools/make-preview.py

Build a standalone copy of the HUD that opens in a browser, so the layout, the twelve gauge
shapes, the ten speedometers and the settings menu can be looked at without starting a server.

It is GENERATED, not maintained: the markup is lifted out of html/index.html and the asset
paths rewritten, so the preview cannot drift from the real page. The boot payload is built by
loading the real config.lua, themes.lua and locale files through a real Lua 5.4 - the preview
is fed exactly what the server would send.

    pip install lupa
    python tools/make-preview.py            # French, the default locale
    python tools/make-preview.py --lang en

Writes preview/index.html. That directory is gitignored.
"""

import argparse
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HASH_LITERAL = re.compile(r'`[^`\n]*`')


def read(*parts):
    return io.open(os.path.join(ROOT, *parts), encoding='utf-8').read()


def build_payload(lang):
    """The boot payload, built by running the resource's own shared Lua."""
    try:
        import lupa
    except ImportError:
        sys.exit('lupa is required: pip install lupa')

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        _G.GetCurrentResourceName = function() return 'v-hud' end
        _G.GetConvar = function(name, default)
            if name == 'hud_locale' then return LANG end
            return default
        end
        _G.print = function() end
    ''')
    lua.globals().LANG = lang

    for rel in ['bridge/shared/hud.lua', 'bridge/shared/locale.lua',
                'locales/en.lua', 'locales/fr.lua', 'config.lua',
                'shared/themes.lua', 'shared/speedometers.lua', 'shared/settings.lua']:
        lua.execute(HASH_LITERAL.sub('0', read(*rel.split('/'))))

    to_json = lua.eval('''
        function()
            local function encode(value, seen)
                local kind = type(value)
                if kind == 'number' or kind == 'boolean' then return tostring(value) end
                if kind == 'string' then
                    return '"' .. value:gsub('[\\\\"]', '\\\\%0'):gsub('\\n', '\\\\n') .. '"'
                end
                if kind ~= 'table' then return 'null' end

                local isArray, count = true, 0
                for key in pairs(value) do
                    count = count + 1
                    if type(key) ~= 'number' then isArray = false end
                end
                if count == 0 then return '{}' end

                local parts = {}
                if isArray then
                    for i = 1, count do parts[#parts + 1] = encode(value[i], seen) end
                    return '[' .. table.concat(parts, ',') .. ']'
                end
                for key, item in pairs(value) do
                    parts[#parts + 1] = '"' .. tostring(key) .. '":' .. encode(item, seen)
                end
                return '{' .. table.concat(parts, ',') .. '}'
            end

            return encode({
                version = '1.0.0',
                locale = CurrentLocale(),
                strings = LocaleTable(),
                themes = Themes.list(),
                speedometers = Speedometers.list(),
                layouts = Settings.layoutPresets(),
                statuses = Config.Status,
                locked = Settings.lockedPaths(),
                bounds = Config.Policy.bounds,
                money = Config.Money,
                notifications = Config.Notifications,
                menu = Config.Menu,
                defaults = Settings.default(),
            })
        end
    ''')

    static = json.loads(to_json())
    settings = static['defaults']
    return static, settings


HARNESS = """
<div id="preview-bar">
  <strong>v-hud preview</strong>
  <label>Theme <select id="pv-theme"></select></label>
  <label>Gauge <select id="pv-gauge"></select></label>
  <label>Speedo <select id="pv-speedo"></select></label>
  <label>Compass <select id="pv-compass"></select></label>
  <label>Surface <select id="pv-surface"></select></label>
  <label><input type="checkbox" id="pv-vehicle" checked> in a vehicle</label>
  <button id="pv-menu">menu</button>
  <button id="pv-layout">move</button>
</div>

<script>
/* The preview harness. Stands in for the Lua side: it posts the same messages the game does
   and answers the same NUI callbacks, so every code path below app.js is the real one. */
(() => {
    const STATIC = __STATIC__;
    let settings = __SETTINGS__;

    const THEMES = __THEME_PATCHES__;

    /* Stand in for the NUI endpoint. The real one is a fetch to https://v-hud/<name>. */
    const originalFetch = window.fetch;
    window.fetch = (url, options) => {
        const name = String(url).split('/').pop();
        let body = {};
        try { body = JSON.parse(options.body); } catch (e) { /* no body */ }
        handle(name, body);
        return Promise.resolve({ json: () => Promise.resolve({}) });
    };

    function deepSet(target, path, value) {
        const parts = path.split('.');
        let node = target;
        for (let i = 0; i < parts.length - 1; i += 1) node = node[parts[i]];
        node[parts[parts.length - 1]] = value;
    }

    function overlay(base, patch) {
        for (const [key, value] of Object.entries(patch || {})) {
            if (value && typeof value === 'object' && !Array.isArray(value)) {
                base[key] = base[key] || {};
                overlay(base[key], value);
            } else {
                base[key] = value;
            }
        }
        return base;
    }

    function push() {
        window.postMessage({ action: 'settings', settings, locked: STATIC.locked }, '*');
        syncControls();
    }

    function handle(name, body) {
        if (name === 'setPath') { deepSet(settings, body.path, body.value); push(); }
        else if (name === 'setPaths') {
            for (const [path, value] of Object.entries(body.changes)) deepSet(settings, path, value);
            push();
        }
        else if (name === 'applyTheme') { overlay(settings, THEMES[body.theme]); settings.theme = body.theme; push(); }
        else if (name === 'applyLayout') {
            const preset = STATIC.layouts.find((l) => l.key === body.layout);
            if (preset) settings.positions = JSON.parse(JSON.stringify(preset.positions));
            push();
        }
        else if (name === 'reset') { settings = JSON.parse(JSON.stringify(STATIC.defaults)); push(); }
        else if (name === 'resetSection') {
            const parts = body.section.split('.');
            let src = STATIC.defaults; let dst = settings;
            for (let i = 0; i < parts.length - 1; i += 1) { src = src[parts[i]]; dst = dst[parts[i]]; }
            dst[parts[parts.length - 1]] = JSON.parse(JSON.stringify(src[parts[parts.length - 1]]));
            push();
        }
        else if (name === 'close') { document.getElementById('menu').hidden = true; }
        else if (name === 'layoutMode') { /* the overlay drives itself */ }
    }

    /* Boot, then a tick loop that animates so the gauges and the speedometer move. */
    window.postMessage({ action: 'boot', static: STATIC, settings }, '*');
    window.postMessage({
        action: 'minimap', shape: settings.minimap.shape, borders: settings.minimap.borders,
        x: settings.minimap.x, y: settings.minimap.y, scale: settings.minimap.scale,
    }, '*');
    window.postMessage({
        action: 'streets', show: true, street: 'Vespucci Boulevard',
        crossing: 'Prosperity Street', zone: 'Vespucci Beach',
    }, '*');
    window.postMessage({ action: 'heading', cardinal: 'N' }, '*');
    window.postMessage({ action: 'showAccount', account: 'cash', amount: 24350, duration: 999999 }, '*');

    let t = 0;
    setInterval(() => {
        t += 0.05;
        const wave = (offset, span) => Math.round(50 + Math.sin(t + offset) * span);
        const inVehicle = document.getElementById('pv-vehicle').checked;
        const speed = Math.round(70 + Math.sin(t * 0.6) * 60);

        window.postMessage({
            action: 'tick',
            show: true,
            health: wave(0, 45), armor: wave(1, 40), hunger: wave(2, 35),
            thirst: wave(3, 38), stress: wave(4, 44), oxygen: wave(5, 30),
            stamina: wave(6, 40), underwater: false, sprinting: true,
            voiceRange: 2, talking: Math.sin(t) > 0, radio: 12, radioActive: true,
            armed: Math.sin(t * 0.4) > 0, parachute: -1, inVehicle,
            vehicle: inVehicle ? {
                speed, maxSpeed: 260, rpm: (Math.sin(t) + 1) / 2, gear: String(1 + (Math.floor(t) % 6)),
                fuel: Math.round(40 + Math.sin(t * 0.3) * 35), range: 180, engine: 82,
                seatbelt: Math.sin(t * 0.5) > 0, cruise: false, nitro: 60, nitroActive: Math.sin(t) > 0.6,
                harness: 20, hasHarness: true, aircraft: false, bicycle: false, driver: true,
                lights: { on: true, high: false, left: Math.sin(t) > 0.7, right: false },
            } : null,
        }, '*');

        window.postMessage({
            action: 'compass', show: true,
            degrees: Math.round((t * 12) % 360),
            cardinal: ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][Math.floor(((t * 12) % 360) / 45)],
        }, '*');
    }, 50);

    /* The toolbar. */
    function option(select, value, label) {
        select.appendChild(Object.assign(document.createElement('option'), { value, textContent: label }));
    }

    const themeSelect = document.getElementById('pv-theme');
    for (const theme of STATIC.themes) option(themeSelect, theme.key, theme.label);
    themeSelect.addEventListener('change', () => handle('applyTheme', { theme: themeSelect.value }));

    const gauge = document.getElementById('pv-gauge');
    for (const shape of ['square', 'rounded', 'pill', 'circle', 'ring', 'radial',
                         'dot', 'bar', 'segment', 'diamond', 'hex', 'icon']) option(gauge, shape, shape);
    gauge.addEventListener('change', () => handle('setPath', { path: 'style.gauge', value: gauge.value }));

    const speedo = document.getElementById('pv-speedo');
    for (const entry of STATIC.speedometers) option(speedo, entry.key, entry.key);
    speedo.addEventListener('change', () => handle('setPath', { path: 'speedometer.style', value: speedo.value }));

    const compass = document.getElementById('pv-compass');
    for (const style of ['bar', 'tape', 'dial', 'text']) option(compass, style, style);
    compass.addEventListener('change', () => handle('setPath', { path: 'compass.style', value: compass.value }));

    const surface = document.getElementById('pv-surface');
    for (const kind of ['glass', 'tint', 'solid', 'none']) option(surface, kind, kind);
    surface.addEventListener('change', () => handle('setPath', { path: 'style.surface', value: surface.value }));

    function syncControls() {
        themeSelect.value = settings.theme;
        gauge.value = settings.style.gauge;
        speedo.value = settings.speedometer.style;
        compass.value = settings.compass.style;
        surface.value = settings.style.surface;
    }
    syncControls();

    document.getElementById('pv-menu').addEventListener('click', () => {
        window.postMessage({
            action: 'openMenu', settings, locked: STATIC.locked,
            providers: { framework: 'qb-core', fuel: 'rcore_fuel', voice: 'pma-voice',
                         notify: 'qb-core', sounds: 'interact-sound', inventory: 'qb-inventory' },
        }, '*');
    });

    document.getElementById('pv-layout').addEventListener('click', () => {
        window.postMessage({ action: 'layoutMode', on: true }, '*');
    });
})();
</script>
"""

PREVIEW_CSS = """
/* Preview chrome only. None of this ships. */
html, body { pointer-events: auto; }
body {
    background:
        radial-gradient(1200px 700px at 22% 78%, #2a1140 0%, transparent 60%),
        radial-gradient(900px 600px at 78% 22%, #10304a 0%, transparent 55%),
        linear-gradient(160deg, #090a12 0%, #16091f 55%, #05070d 100%);
}
/* A stand-in for the game minimap, drawn from the SAME --map-* variables the real frame and
   the docked elements use. That is the point: if the placeholder and the border disagree
   here, they disagree in game too. */
body::after {
    content: 'MINIMAP';
    position: fixed;
    left: var(--map-left);
    bottom: var(--map-bottom);
    width: var(--map-w);
    height: var(--map-h);
    display: flex; align-items: center; justify-content: center;
    background: repeating-linear-gradient(45deg, #1d2733 0 12px, #232f3d 12px 24px);
    color: rgba(255,255,255,0.35); font-size: 12px; letter-spacing: 0.3em;
    z-index: 1;
    border-radius: var(--map-radius, 0);
}
/* The toolbar sits at the BOTTOM. At the top it covered the compass, the money row and the
   whole top third of the HUD, which is exactly the part a preview exists to show. */
#preview-bar {
    position: fixed; bottom: 0; left: 0; right: 0; z-index: 999;
    display: flex; align-items: center; gap: 14px; flex-wrap: wrap;
    padding: 8px 14px; background: #0d0f16; border-bottom: 1px solid #262b3a;
    font: 12px/1.4 system-ui, sans-serif; color: #cbd5e1; pointer-events: auto;
}
#preview-bar label { display: flex; align-items: center; gap: 5px; }
#preview-bar select, #preview-bar button {
    background: #1a1f2e; color: #e2e8f0; border: 1px solid #2f3648;
    border-radius: 4px; padding: 3px 7px; font: inherit;
}
#preview-bar button { cursor: pointer; }
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lang', default='fr')
    args = parser.parse_args()

    static, settings = build_payload(args.lang)

    # Theme patches, so the preview's stand-in for the Lua side can apply one.
    import lupa
    lua = lupa.LuaRuntime()
    themes = {}
    for theme in static['themes']:
        themes[theme['key']] = None
    # Re-run the shared Lua once more, this time to dump each patch.
    # Cheaper than threading it through build_payload's single return.
    lua.execute('''
        _G.GetCurrentResourceName = function() return 'v-hud' end
        _G.GetConvar = function(_, d) return d end
        _G.print = function() end
    ''')
    for rel in ['bridge/shared/hud.lua', 'bridge/shared/locale.lua', 'locales/en.lua',
                'locales/fr.lua', 'config.lua', 'shared/themes.lua',
                'shared/speedometers.lua', 'shared/settings.lua']:
        lua.execute(HASH_LITERAL.sub('0', read(*rel.split('/'))))

    def to_python(value):
        if lupa.lua_type(value) != 'table':
            return value
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_python(value[k]) for k in sorted(keys)]
        return {str(k): to_python(value[k]) for k in keys}

    lua_themes = lua.globals().Themes
    for key in list(themes):
        themes[key] = to_python(lua_themes[key].patch)

    # The markup, lifted straight out of the shipped page so the two cannot drift.
    page = read('html', 'index.html')
    body = re.search(r'<body>(.*)</body>', page, re.S).group(1)
    body = body.replace('href="css/', 'href="../html/css/')
    body = body.replace('src="js/', 'src="../html/js/')

    head_links = re.findall(r'<link[^>]+>', page)
    head = '\n    '.join(link.replace('href="css/', 'href="../html/css/') for link in head_links)

    harness = (HARNESS
               .replace('__STATIC__', json.dumps(static, ensure_ascii=False))
               .replace('__SETTINGS__', json.dumps(settings, ensure_ascii=False))
               .replace('__THEME_PATCHES__', json.dumps(themes, ensure_ascii=False)))

    out = (
        '<!DOCTYPE html>\n<html lang="%s">\n<head>\n'
        '    <meta charset="utf-8">\n'
        '    <title>v-hud preview</title>\n    %s\n'
        '    <style>%s</style>\n</head>\n<body>\n%s\n%s\n</body>\n</html>\n'
    ) % (args.lang, head, PREVIEW_CSS, body, harness)

    target = os.path.join(ROOT, 'preview')
    os.makedirs(target, exist_ok=True)
    path = os.path.join(target, 'index.html')
    io.open(path, 'w', encoding='utf-8', newline='').write(out)

    print('wrote %s (%s, %d strings, %d themes, %d speedometers)'
          % (path, args.lang, len(static['strings']), len(static['themes']),
             len(static['speedometers'])))


if __name__ == '__main__':
    main()
