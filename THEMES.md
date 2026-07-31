# Writing a theme

A theme is a **patch**, not a settings file. It moves the keys it names and leaves everything
else alone — which is why trying a theme never costs a player the layout they arranged, or the
elements they switched off.

Three ways to add one, in order of how permanent you want it.

---

## 1. Straight in config.lua — one theme, five minutes

For a single house theme. Nothing to create, nothing to register.

```lua
Config.ExtraThemes = {
    ['midnight'] = {
        label = 'Midnight',
        swatch = { '#04060d', '#5b8cff', '#8be9fd' },
        patch = {
            style   = { gauge = 'rounded', surface = 'tint', glow = false, corner = 8 },
            colours = { accent = '#5b8cff', background = '#04060d', text = '#dbe6ff' },
            minimap = { shape = 'square', borders = true },
            speedometer = { style = 'luxury' },
            compass = { style = 'bar' },
        },
    },
}
```

Then make it selectable:

```lua
Config.Policy.themes = { 'glass', 'square', 'miami', 'neon', 'modern', 'midnight' }
```

`restart v-hud`. It is in the picker.

A key that is already a shipped theme **customises** that theme rather than shadowing it — so
`['glass'] = { patch = { colours = { accent = '#00ff00' } } }` gives you Clear Glass with a
different accent and nothing else changed.

## 2. Its own file — a theme you will keep working on

Copy `themes/example.lua`, which is a complete annotated theme:

```
themes/midnight.lua
```

```lua
Themes.midnight = {
    key = 'midnight',
    label = 'Midnight',
    swatch = { '#04060d', '#5b8cff', '#8be9fd' },
    patch = { ... },
}
```

Add it to `fxmanifest.lua`, in `shared_scripts`, after `shared/themes.lua`:

```lua
'themes/midnight.lua',
```

and to `Config.Policy.themes`. That is all.

**Why the file is named rather than globbed.** `themes/*.lua` looks tidier and costs you a
warning on every restart when it matches nothing, and it does not resolve at all when the
resource is installed as a junction to a git checkout — which is how anybody developing
against it runs it. One line per theme is the price.

## 3. From your own resource — a theme you ship separately

```lua
exports['v-hud']:RegisterTheme('midnight', {
    label = 'Midnight',
    swatch = { '#04060d', '#5b8cff', '#8be9fd' },
    patch = { colours = { accent = '#5b8cff' } },
})
```

Call it once on startup, after v-hud has started. The key still has to be in
`Config.Policy.themes`, because what is *offered* is the server owner's decision, not the
theme author's.

---

## What a patch may contain

Every key is optional. Name only what your theme has an opinion about.

| Key | Values |
|---|---|
| `style.gauge` | `square` `rounded` `pill` `circle` `ring` `radial` `dot` `bar` `segment` `diamond` `hex` `icon` |
| `style.direction` | `row` `column` |
| `style.surface` | `glass` `tint` `solid` `none` |
| `style.blur` | `0`–`32`, only used by `glass` |
| `style.icons` `values` `hideFull` `outline` `glow` | `true` / `false` |
| `style.corner` | px, or `999` for fully round |
| `style.gap` | px between gauges |
| `colours.*` | six-digit hex, `#rrggbb` |
| `minimap.shape` | `square` `circle` |
| `minimap.borders` | `true` / `false` |
| `speedometer.style` | `minimal` `classic` `sport` `digital` `luxury` `jdm` `muscle` `supercar` `truck` `retro` |
| `compass.style` | `bar` `tape` `dial` `text` |

Colour keys: `accent`, `health`, `armor`, `hunger`, `thirst`, `stress`, `oxygen`, `stamina`,
`voice`, `speed`, `fuel`, `rpm`, `warning`, `background`, `text` — plus one per custom gauge
you added to `Config.Status`.

**A patch never contains `positions`.** Layout belongs to the player, and a theme that moved
their HUD would be a theme nobody dares try. If you want to ship an arrangement, add a
`Config.LayoutPresets` entry instead — those are chosen separately and knowingly.

## What the validator will do to your theme

Everything goes through the same pipeline as a player's own settings:

1. **Merged into the schema.** A key that does not exist is dropped. A misspelled `colour`
   costs you that colour, not the theme.
2. **Coerced.** A colour that is not six hex digits becomes the default for that key. A value
   outside `Config.Policy.bounds` is clamped. An unknown enum falls back.
3. **Policed.** `Config.Policy.forcedStyle`, `forcedColours` and `locked` win over your theme,
   always. A server owner's decision outranks a theme author's.

So a broken theme degrades to a slightly-wrong theme. It cannot break the HUD.

## Two things you cannot theme

By design, and enforced in code rather than by convention:

- **Element positions.** The player arranges their own screen.
- **The minimap shape.** The player picks square or round.

Your theme may *suggest* a minimap shape — it is applied when the theme is selected — but the
player can change it straight back, and no server policy can stop them.

## Testing without a server

```bash
python tools/make-preview.py --lang fr
```

Open `preview/index.html`. Every theme, every gauge shape, every cluster and the whole
settings menu, driven by the real files with synthetic data. The theme dropdown in the toolbar
picks yours up as soon as it is in `Config.Policy.themes`.

## Design notes worth knowing

**There is no real blur.** `surface = 'glass'` is a translucent gradient with a lit top edge
and a drop shadow. FiveM's CEF composites the page *over* the finished game frame, so
`backdrop-filter` has nothing behind it to sample and paints a solid black rectangle. If you
are used to designing glass on the web, this is the one habit to unlearn.

**Nothing newer than a 2022 Chromium.** No `color-mix()`, no `oklch()`, no `:has()`, no
container queries. An unsupported function invalidates the whole declaration silently, which
is a very quiet way to lose a background. Blends are computed in JS and published as custom
properties — see `--c-accent-a18`, `--c-bg-d88` in `html/js/state.js`.

**Colours reach CSS as custom properties.** `colours.accent` becomes `--c-accent`, and
everything on screen reads it. That is why a colour picker recolours the HUD live with no
re-render: one property changes and the browser repaints.

---

# Écrire un thème (Version Française)

Un thème est un **correctif**, pas un fichier de réglages. Il déplace les clés qu'il nomme et
laisse le reste tranquille — c'est pour cela qu'essayer un thème ne coûte jamais à un joueur
la disposition qu'il a arrangée.

Trois méthodes, de la plus rapide à la plus pérenne.

## 1. Directement dans config.lua

Ajoutez une entrée à `Config.ExtraThemes`, puis sa clef à `Config.Policy.themes`. Voir
l'exemple commenté en haut de la version anglaise. Une clef qui correspond à un thème livré
**personnalise** ce thème au lieu de le remplacer.

## 2. Son propre fichier

Copiez `themes/example.lua`, qui est un thème complet et annoté. Ajoutez son chemin dans
`fxmanifest.lua` (dans `shared_scripts`, après `shared/themes.lua`) et sa clef dans
`Config.Policy.themes`.

Les fichiers sont nommés un par un plutôt que globalisés : un glob qui ne correspond à rien
affiche un avertissement à chaque redémarrage, et un glob ne se résout pas du tout quand la
ressource est installée en jonction vers un dépôt git.

## 3. Depuis votre propre ressource

```lua
exports['v-hud']:RegisterTheme('midnight', { label = 'Midnight', patch = { ... } })
```

La clef doit tout de même figurer dans `Config.Policy.themes` : ce qui est *proposé* reste la
décision du propriétaire du serveur.

## Deux choses non thématisables

Garanties dans le code, pas par convention :

- **Les positions des éléments.** Le joueur arrange son propre écran.
- **La forme de la minimap.** Le joueur choisit carrée ou ronde.

Votre thème peut *suggérer* une forme de minimap, mais le joueur peut la changer aussitôt et
aucune politique serveur ne peut l'en empêcher.

## À savoir avant de dessiner

**Il n'y a pas de vrai flou.** `surface = 'glass'` est un dégradé translucide avec une arête
lumineuse. Le CEF de FiveM compose la page *par-dessus* l'image finie du jeu : `backdrop-filter`
n'a rien à échantillonner et peint un rectangle noir opaque.

**Rien de plus récent qu'un Chromium de 2022.** Pas de `color-mix()`, `oklch()`, `:has()` ni
requêtes de conteneur. Une fonction inconnue invalide **toute** la déclaration, en silence.

**Tester sans serveur :** `python tools/make-preview.py --lang fr`, puis ouvrez
`preview/index.html`.
