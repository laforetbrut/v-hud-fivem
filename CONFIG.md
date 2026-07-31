# Server owner's guide

Everything in `config.lua`, what it does, and what it costs. Fourteen sections; this covers
the ones you are likely to want.

The file has two halves and the split is the whole design:

- **`Config.Defaults`** is what a player *starts with*. They may change any of it.
- **`Config.Policy`** is what a player *may not change*.

An empty `Policy` means the player owns everything, which is how it ships.

---

## The two promises

Whatever you configure, players keep these. Both are enforced in code — `Settings.isLocked`
refuses them and the server prints a warning if a config tries:

1. **They can always move every element.** `positions` is never lockable.
2. **They can always choose the minimap shape.** `minimap.shape` is never lockable.

You may lock `minimap` as a branch — that covers hide, scale and the offsets — and the shape
will still survive it.

---

## Restricting what is offered

Cut a list and the option disappears from the menu **and** is refused on save. Not offered and
then rejected — simply not there.

```lua
Config.Policy.themes         = { 'glass', 'square' }   -- two themes only
Config.Policy.speedometers   = { 'digital', 'classic' }
Config.Policy.gaugeShapes    = { 'square', 'rounded', 'circle' }
Config.Policy.compassStyles  = { 'bar' }               -- one style: the control disappears
Config.Policy.surfaces       = { 'solid' }             -- no glass on this server
```

A list with **one** entry left is not a choice, so the control is not drawn at all.

**An empty `compassStyles` removes the compass entirely.**

## Forcing a look

```lua
Config.Policy.forcedTheme       = 'glass'      -- everyone runs it, picker locked
Config.Policy.forcedSpeedometer = 'digital'
Config.Policy.forcedStyle       = { surface = 'solid', glow = false, corner = 4 }
Config.Policy.forcedColours     = { accent = '#ff0044', background = '#0a0a0a' }
```

A forced theme is applied **in full** first, then the forced style and colours are pinned on
top of it. So `forcedTheme = 'neon'` plus `forcedColours = { accent = '#fff' }` gives you neon
with a white accent.

## Deciding what each element may do

Three answers per element:

| Value | Meaning |
|---|---|
| `'player'` | The player decides. The switch is in the menu. **Default.** |
| `'forced'` | Always drawn. The switch is shown locked. |
| `'off'` | **Removed from this server.** Not drawn, not computed, and not in the menu. |

```lua
Config.Policy.elements = {
    streets = 'forced',    -- street names are mandatory
    stress  = 'off',       -- this server has no stress mechanic
    dev     = 'off',
    compass = 'player',
}
```

`'off'` is a removal, not a default. The element never enters the tick, so it costs nothing.

Anything you do not list is `'player'`. A gauge you added to `Config.Status` can be listed too.

## Locking anything else

For whatever the switches above do not cover, dotted paths into `Config.Defaults`:

```lua
Config.Policy.locked = {
    'units',              -- km/h only
    'advanced.refresh',   -- everyone runs the rate you chose
    'minimap.hide',       -- nobody may hide the minimap
    'colours.background',
}
```

A path locks itself and everything under it: `'colours'` locks every colour.

## Bounding the sliders

So that "movable" cannot become "moved somewhere nobody can see it":

```lua
Config.Policy.bounds = {
    scale        = { min = 0.60, max = 1.60 },
    opacity      = { min = 0.25, max = 1.00 },
    minimapScale = { min = 0.70, max = 1.50 },
    -- ...
}
```

## Per job and per gang

Applied **on top of** the player's own settings and never saved into them, so quitting the job
gives them their HUD back exactly as it was:

```lua
Config.JobOverrides = {
    ['police']       = { show = { streets = true, compass = true } },
    ['ambulance']    = { show = { stress = false } },
    ['gang:ballas']  = { colours = { accent = '#7c3aed' } },
}
```

Keys are a job name, a job type, or `gang:<name>`. `Config.Policy` still wins over an override.

## Adding your own gauge

`Config.Status` is data. Add an entry and it appears in the HUD, the element list and the
colour picker with no code change:

```lua
{
    key = 'drunk', source = 'metadata', field = 'alcohol', order = 80,
    icon = 'M5 3h14l-6 8v7h3v3H8v-3h3v-7L5 3z',   -- an SVG path, drawn at 24x24
    invert = true, warnAbove = 50, pulse = true,
},
```

`source` is `'native'` (computed by the HUD), `'metadata'` (read from the framework) or
`'event'` (pushed in — see API.md). `invert` means a high value is bad.

## Getting out of the way

```lua
Config.HideWhen = {
    pauseMenu = true,   -- the GTA pause menu, the map screen, the loading screen
    nuiFocus  = true,   -- any other resource holding NUI focus
    resources = {
        { resource = 'v-phone', export = 'IsOpen' },
        -- add your own: a resource and a boolean export it already publishes
    },
}
```

Nothing here reaches into another resource. It asks a question that resource already answers,
and a missing export is recorded once and never asked again.

## Sharing

```lua
Config.Policy.allowSharing      = true   -- export/import codes in the menu
Config.Policy.importKeepsLayout = true   -- an import brings the look, not the layout
```

An imported code goes through the identical validation as any other save — merged into the
schema, coerced, then policed — so a code exported on a server with different rules cannot
carry a locked value onto yours.

## Admin commands

```lua
Config.Policy.adminAce       = 'qbcore.admin'
Config.Policy.allowAdminPush = true
```

```
/hudadmin list
/hudadmin theme neon <id|all>
/hudadmin speedo digital <id|all>
/hudadmin preset minimal <id|all>
/hudadmin reset <id|all>
```

A push is a **patch**, not a replacement: it moves the keys the preset names and leaves the
player's positions and colours alone. `reset` is there for a clean slate.

Presets live in `Config.Presets` and are ordinary settings patches.

## Storage

```lua
Config.Persistence = {
    kvp      = true,               -- per machine, instant, zero dependencies
    database = true,               -- follows the character; needs oxmysql
    prefer   = 'newest',           -- 'newest' | 'database' | 'kvp'
    scope    = 'character',        -- 'character' | 'license'
    debounce = 800,
}
```

With no oxmysql the database half switches itself off and the HUD still works — settings just
stay on the machine they were set on. Tables are created on first start.

## Odometer

GTA keeps no mileage, so it is measured while the player drives and stored per number plate:

```lua
Config.Odometer = {
    enabled   = true,
    providers = { 'odometer', 'mileage', 'jimOdo' },  -- vehicle state bags to read first
    track     = true,                                 -- measure it here when none answered
    saveEvery = 1000,                                 -- metres between writes
    unit      = 'units',                              -- 'units' | 'km' | 'mi'
}
```

If a resource already keeps a mileage, it is read instead — one number beats two that
disagree.

## Refresh rate

```lua
Config.Tick.rates = { [30] = 33, [60] = 16, [90] = 11 }
Config.Tick.defaultRate = 60
```

Every entry is offered to the player; removing one removes the choice.

---

# Guide du propriétaire de serveur (Version Française)

Tout est dans `config.lua`, en quatorze sections commentées. Le fichier a deux moitiés :

- **`Config.Defaults`** : ce avec quoi un joueur *commence*. Il peut tout changer.
- **`Config.Policy`** : ce qu'il *ne peut pas* changer.

## Les deux promesses

Quoi que vous configuriez, les joueurs gardent ceci — garanti dans le code, avec un
avertissement en console si une config essaie :

1. **Ils peuvent toujours déplacer chaque élément.** `positions` n'est jamais verrouillable.
2. **Ils choisissent toujours la forme de la minimap.** `minimap.shape` non plus.

Vous pouvez verrouiller `minimap` en tant que branche — cela couvre le masquage, la taille et
les décalages — la forme y survivra.

## Restreindre ce qui est proposé

Retirez une entrée : l'option disparaît du menu **et** est refusée à la sauvegarde.

```lua
Config.Policy.themes        = { 'glass', 'square' }
Config.Policy.speedometers  = { 'digital', 'classic' }
Config.Policy.gaugeShapes   = { 'square', 'rounded', 'circle' }
Config.Policy.compassStyles = { }          -- boussole retirée du serveur
Config.Policy.surfaces      = { 'solid' }  -- pas de verre ici
```

Une liste à une seule entrée n'est pas un choix : le contrôle n'est pas dessiné.

## Imposer une apparence

```lua
Config.Policy.forcedTheme       = 'glass'
Config.Policy.forcedSpeedometer = 'digital'
Config.Policy.forcedStyle       = { surface = 'solid', glow = false }
Config.Policy.forcedColours     = { accent = '#ff0044' }
```

## Décider élément par élément

`'player'` (le joueur décide), `'forced'` (toujours affiché), `'off'` (**supprimé du
serveur** : ni dessiné, ni calculé, ni présent dans le menu).

```lua
Config.Policy.elements = { streets = 'forced', stress = 'off', dev = 'off' }
```

## Le reste

Verrouillages libres par chemin (`Config.Policy.locked`), bornes de curseurs
(`Config.Policy.bounds`), surcharges par métier et gang (`Config.JobOverrides`), jauges
personnalisées (`Config.Status`), effacement sous les autres interfaces (`Config.HideWhen`),
partage de configuration (`Config.Policy.allowSharing`), stockage (`Config.Persistence`),
kilométrage (`Config.Odometer`) et fréquence de rafraîchissement (`Config.Tick.rates`).

Chaque section de `config.lua` est commentée en détail, avec le *pourquoi* de chaque réglage.
