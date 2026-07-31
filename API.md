# API

Everything another resource may call, and every event this one answers.

Nothing here is required to use v-hud. It is here so a mechanic script can read a mileage, a
drug script can add stress, and a menu resource can open the settings panel.

---

## Client exports

```lua
-- Settings
local settings = exports['v-hud']:GetSettings()          -- a copy, or nil before boot
exports['v-hud']:SetSettings({ compact = true })         -- a patch; policed like any save

-- The menu
exports['v-hud']:OpenMenu()
exports['v-hud']:CloseMenu()
local open = exports['v-hud']:IsMenuOpen()

-- Notifications, in the player's own theme
exports['v-hud']:Notify('Engine damaged', 'error', 4000)   -- kind: primary | success | error

-- Stress. The client asks; the SERVER decides.
exports['v-hud']:AddStress(10)
exports['v-hud']:RemoveStress(10)
local needs = exports['v-hud']:GetNeeds()                -- { hunger, thirst, stress }

-- Where the player is
local where = exports['v-hud']:GetLocation()
-- { street, crossing, zone, heading, cardinal }

-- Odometer, in metres, or nil when nothing is tracking one
local metres = exports['v-hud']:GetOdometer(vehicle)

-- Themes (see THEMES.md)
exports['v-hud']:RegisterTheme('midnight', { label = 'Midnight', patch = { ... } })
local themes = exports['v-hud']:GetThemes()
```

`SetSettings` is a **patch**, not a replacement: it moves the keys it names. It goes through
the same validation as anything else, so it cannot set a value the server locked.

## Server exports

```lua
-- Stress. Returns the new level, or nil when nothing changed.
exports['v-hud']:AddStress(source, 10)
exports['v-hud']:RemoveStress(source, 10)
exports['v-hud']:SetStress(source, 0)
local stress = exports['v-hud']:GetStress(source)

-- Push settings to a player, or reset them
exports['v-hud']:PushSettings(source, { theme = 'neon' }, 'Your HUD was changed')
exports['v-hud']:ResetSettings(source)

-- Odometer, by number plate
local metres = exports['v-hud']:GetOdometer('ABC 123')
exports['v-hud']:SetOdometer('ABC 123', 0)               -- a rebuilt engine, an import
```

## Events this resource answers

Every event stock qb-hud handled, so no other resource needs editing when you swap them:

| Event | Side | Effect |
|---|---|---|
| `hud:client:UpdateNeeds(hunger, thirst)` | client | Hunger and thirst gauges |
| `hud:client:UpdateStress(stress)` | client | Stress gauge |
| `hud:client:UpdateNitrous(level, active)` | client | Nitrous gauge |
| `hud:client:UpdateHarness(hp)` | client | Harness ring |
| `hud:client:ShowAccounts(account, amount)` | client | Balance toast |
| `hud:client:LoadMap()` | client | Re-apply the minimap |
| `hud:client:ToggleAirHud()` | client | Altitude readout |
| `hud:client:ToggleShowSeatbelt()` | client | Seatbelt tell-tale |
| `hud:server:GainStress(amount)` | server | Add stress |
| `hud:server:RelieveStress(amount)` | server | Remove stress |
| `hud:server:getMenu` | server | QBCore callback, answered with the defaults |
| `seatbelt:client:ToggleSeatbelt` | client | Belt tell-tale |
| `seatbelt:client:ToggleCruise` | client | Cruise tell-tale |

Its own names, for anything new:

| Event | Side |
|---|---|
| `vhud:client:UpdateNeeds(hunger, thirst)` | client |
| `vhud:client:UpdateStress(stress)` | client |
| `vhud:client:UpdateStatus(key, value)` | client — a custom `Config.Status` gauge |
| `vhud:client:UpdateNitrous(level, active)` | client |
| `vhud:client:UpdateHarness(hp)` | client |
| `vhud:client:LoadMap()` | client |
| `vhud:server:GainStress(amount)` | server |
| `vhud:server:RelieveStress(amount)` | server |

`Config.Compat.qbHudEvents = false` turns the `hud:*` half off, for a server that still runs
qb-hud alongside — which is not a supported configuration.

## Feeding a custom gauge

Add it to `Config.Status` with `source = 'event'`, then push values:

```lua
TriggerClientEvent('vhud:client:UpdateStatus', source, 'radiation', 62)
```

Or with `source = 'metadata'` and a `field`, and the HUD reads the framework's player metadata
itself — nothing to push at all.

## State bags read

| Bag | On | Used for |
|---|---|---|
| `proximity` | player | Voice range |
| `radioChannel` | player | Radio channel |
| `seatbelt` | player | Belt state, for scripts that publish rather than fire |
| `fuel` | vehicle | ox_fuel |
| `hasnitro`, `noslevel` | vehicle | jim-mechanic NOS |
| `odometer`, `mileage`, `jimOdo` | vehicle | An existing mileage |

All configurable in `Config.Compat` and `Config.Odometer`.

## Database

Two tables, both created on first start, both optional:

| Table | Holds |
|---|---|
| `vhud_settings` | `identifier`, `settings` (JSON), `updated_at` |
| `vhud_odometer` | `plate`, `metres` |

Names are configurable. With no oxmysql neither is created and the HUD still runs.

---

# API (Version Française)

Rien ici n'est nécessaire pour utiliser v-hud. C'est là pour qu'un script de mécanique puisse
lire un kilométrage, qu'un script de drogue puisse ajouter du stress, et qu'une ressource de
menu puisse ouvrir le panneau de réglages.

Les tableaux ci-dessus se lisent tels quels. Les points à retenir :

- **`SetSettings` est un correctif**, pas un remplacement : il déplace les clefs qu'il nomme,
  et passe par la même validation que n'importe quelle sauvegarde. Il ne peut donc pas poser
  une valeur que le serveur a verrouillée.
- **Le stress est décidé par le serveur.** Le client demande, il n'impose pas. Un client
  capable de fixer son propre stress pourrait le mettre à zéro, et le mécanisme entier
  deviendrait décoratif.
- **Tous les événements de qb-hud reçoivent une réponse**, donc aucune autre ressource n'a
  besoin d'être modifiée quand vous remplacez l'un par l'autre.
- **Une jauge personnalisée** s'ajoute dans `Config.Status`. Avec `source = 'metadata'` elle
  se lit toute seule depuis les métadonnées du framework : il n'y a rien à envoyer.
