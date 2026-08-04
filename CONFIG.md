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

A HUD over somebody's phone is in the way. A HUD that vanishes because a radial menu drew a
wheel around the crosshair is broken. `Config.HideWhen` is where you draw that line.

**Why it needs configuring:** when a resource opens a menu it calls `SetNuiFocus`. The HUD can
see that *something* took focus, but FiveM has no native that says *which* resource has it — a
phone covering the screen and a target eye drawing a dot look identical from here.

**The catch-all rule** decides what happens for a menu you have not listed:

```lua
Config.HideWhen.onFocus = 'auto'   -- 'auto' | 'hide' | 'show'
```

| Value | Behaviour |
|---|---|
| `'auto'` | **Default, and needs no setup.** Asks the game whether the thing holding focus kept *game input* alive. Input kept → you can still walk and drive under it, so it is an overlay and the HUD stays. Input taken → it is a screen and the HUD hides. This sorts target eyes and walk-while-open radial menus from phones and inventories with no per-resource work. |
| `'hide'` | Step aside for any focus at all. Safest, and the most annoying. |
| `'show'` | Never hide on focus alone — only the game's screens and the listed resources hide it. Closest to qb-hud. |

**Per resource**, checked before the catch-all. A specific answer always beats a general one:

```lua
Config.HideWhen.resources = {
    { resource = 'v-phone', export = { 'IsOpen', 'isOpen' } },   -- hides everything
    { resource = 'qb-radialmenu', when = 'show',                 -- never hides the HUD
      openEvent  = 'qb-radialmenu:client:onRadialmenuOpen',
      closeEvent = 'qb-radialmenu:client:onRadialmenuClose' },
    { resource = 'qb-menu', when = 'hide',                       -- takes the gauges only
      hides = { hud = true, minimap = false } },
}
```

Three ways to detect a resource, any one of them: an `export` (a name, or several candidates —
the first that answers wins), an `openEvent`/`closeEvent` pair, or a `stateBag`. A resource
that is not started, or whose export does not exist on your build, is skipped silently — a
wrong entry here can never break anything.

The order things are decided in:

1. The game's own screens (`pauseMenu`, `frontend`) — always hide.
2. A listed resource that is open with `when = 'show'` — **always stay up**, beats everything below.
3. A listed resource that is open with `when = 'hide'` — hide what its `hides` names.
4. Focus held by something unlisted — whatever `onFocus` says.

## Which framework you are on

Detected at runtime, in this order: **qb-core**, **qbx_core**, **es_extended** (ESX),
**ox_core**. The first whose resource is started *and* whose handshake answers is used;
anything else runs standalone, which is a supported configuration rather than a failure —
settings still save to the client's own storage, stress is simply not persisted, and nothing
errors.

```lua
Config.Compat.forceFramework = 'qb-core'   -- skip detection; nil means detect
```

Set it on a server that has two installed — a qb-core server keeping `es_extended` around for
one legacy script would otherwise be decided by start order.

**What actually differs.** Everything below is a property of the framework, not a gap in the
HUD, and `/hudinfo` prints which one answered:

| | qb-core / qbx_core | es_extended | ox_core |
|---|---|---|---|
| Job | yes | yes | first group |
| Job type | `job.type` | job **grade** stands in | group rank |
| Gang | yes | **none** — `gang:name` overrides never match | **none** |
| Hunger / thirst | player metadata | **`esx_status`**, read directly | player metadata |
| Stress | player metadata | not a concept; the HUD keeps its own | player metadata |
| Notifications | framework | `esx:showNotification` | **HUD toast** (ox ships none) |
| Commands in chat suggestions | yes | yes | plain `RegisterCommand` |
| Settings key | `citizenid` | `identifier` | `stateId` |

Nothing above needs configuring. It is here so that a missing gang override or a differently
styled notification reads as expected rather than as a bug.

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

## Warning lamp thresholds

When the cluster's lamps come on. Separate from `Config.Alerts`, which is about sounds.

```lua
Config.Cluster = {
    lowFuel         = 25,   -- reserve light, as a percentage of the tank
    lowFuelCritical = 8,    -- below this it blinks instead of sitting steady
    engineFault     = 25,   -- engine health below this lights the engine lamp red
}
```

`Config.Compat.partWarning` (default 50) does the same job for the mechanical wear lamps.

## Warning sounds

Three of them, all under `Config.Alerts`, and all silent for a player who turned HUD sounds
off in the settings menu — this is your ceiling, not an override.

```lua
Config.Alerts = {
    speed = 40,        -- driving warnings only sound above this, in the player's own unit
    grace = 1200,      -- ms the fault must hold first, so a tap at a junction is silent

    seatbelt = { enabled = true,  interval = 2500, sound = 'Beep_Red',
                 set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },

    -- Off, and it should usually stay off: a door that reads as open is very often a door
    -- that is BROKEN, and a chime you cannot silence by driving properly trains players to
    -- ignore every other warning. The tell-tale on the cluster still lights.
    door     = { enabled = false, interval = 4000, sound = 'CHECKPOINT_MISSED',
                 set = 'HUD_MINI_GAME_SOUNDSET' },

    includeBootAndBonnet = false,   -- a mechanic script leaves the bonnet up; not a fault

    growl = {
        enabled    = true,
        thresholds = { 10, 5, 0 },  -- percentages of hunger/thirst REMAINING
        rearm      = 3,             -- how far back above a threshold before it can fire again
        seconds    = 3.5,           -- hard cap on the length
        volume     = 0.5,
        cooldown   = 8000,          -- ms, so hunger and thirst crossing together is one sound

        useGameSound = false,       -- fall back to a frontend sound if page audio is blocked
        sound = 'Beep_Red', set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
    },
}
```

The growl is edge-triggered on the way **down**. Sitting at 4% is silent; eating back above
`threshold + rearm` and starving again growls afresh; climbing back up never growls. The sound
itself is synthesised by the NUI page — there is no audio file to ship, and `seconds` is an
exact cap rather than whatever length a file happens to be.

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

## Sons d'alerte

Trois, tous dans `Config.Alerts`, tous muets pour un joueur qui a coupé les sons du HUD dans
le menu : ceci est votre plafond, pas une surcharge.

- **Ceinture** (`seatbelt`) : active. Sonne au-delà de `speed`, après `grace` ms de maintien,
  puis toutes les `interval` ms.
- **Porte ouverte** (`door`) : **désactivée**, et il vaut mieux la laisser ainsi. Une porte
  signalée ouverte est très souvent une porte *cassée*, et une alerte qu'on ne peut pas faire
  taire en conduisant correctement apprend à ignorer toutes les autres. Le témoin sur le
  compteur reste allumé.
- **Gargouillement** (`growl`) : se déclenche en **descendant** à travers 10 %, 5 % et 0 % de
  faim ou de soif. Rester à 4 % est silencieux ; remanger au-dessus de `threshold + rearm`
  puis redescendre redéclenche ; remonter ne déclenche jamais. Le son est synthétisé par la
  page NUI : aucun fichier audio à livrer, et `seconds` est une durée exacte.

## Sur quel framework vous êtes

Détecté à l'exécution, dans cet ordre : **qb-core**, **qbx_core**, **es_extended** (ESX),
**ox_core**. Le premier dont la ressource est démarrée *et* dont la poignée de main répond est
retenu ; tout le reste tourne en standalone, ce qui est une configuration prise en charge et
non un échec : les réglages se sauvegardent toujours côté client, le stress n'est simplement
pas persisté, et rien ne lève d'erreur.

```lua
Config.Compat.forceFramework = 'qb-core'   -- court-circuite la détection ; nil = détecter
```

À poser sur un serveur qui en a deux installés : un serveur qb-core qui garde `es_extended`
pour un script hérité serait sinon départagé par l'ordre de démarrage.

**Ce qui diffère réellement.** Tout ce qui suit est une propriété du framework, pas un manque
du HUD, et `/hudinfo` indique lequel a répondu :

| | qb-core / qbx_core | es_extended | ox_core |
|---|---|---|---|
| Métier | oui | oui | premier groupe |
| Type de métier | `job.type` | le **grade** en tient lieu | rang du groupe |
| Gang | oui | **aucun** — les surcharges `gang:nom` ne matchent jamais | **aucun** |
| Faim / soif | métadonnées joueur | **`esx_status`**, lu directement | métadonnées joueur |
| Stress | métadonnées joueur | pas un concept ; le HUD garde le sien | métadonnées joueur |
| Notifications | framework | `esx:showNotification` | **toast du HUD** (ox n'en a pas) |
| Suggestions de chat | oui | oui | `RegisterCommand` simple |
| Clé de sauvegarde | `citizenid` | `identifier` | `stateId` |

Rien de tout cela ne demande de configuration. C'est écrit ici pour qu'une surcharge de gang
sans effet ou une notification d'un autre style se lise comme attendu, et non comme un bug.

## Le reste

Verrouillages libres par chemin (`Config.Policy.locked`), bornes de curseurs
(`Config.Policy.bounds`), surcharges par métier et gang (`Config.JobOverrides`), jauges
personnalisées (`Config.Status`), effacement sous les autres interfaces (`Config.HideWhen`),
partage de configuration (`Config.Policy.allowSharing`), stockage (`Config.Persistence`),
kilométrage (`Config.Odometer`) et fréquence de rafraîchissement (`Config.Tick.rates`).

Chaque section de `config.lua` est commentée en détail, avec le *pourquoi* de chaque réglage.
