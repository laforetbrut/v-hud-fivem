# v-hud

A fully customisable HUD for QBCore. Every player owns their own HUD: every element can be
moved by dragging it, recoloured, reshaped, resized or switched off, and the server owner
decides which of those freedoms to leave open. Ships with five themes, twelve gauge shapes,
ten realistic instrument clusters, four compasses and a frosted-glass default look.

## Features

- **Clear Glass default theme** - translucent panels with a real backdrop blur, hot pink
  accent, Vice City palette. Four more ship with it: square minimalist, Miami, neon, modern.
- **Everything is movable** - a drag editor with snap-to-grid, six layout presets, and
  per-element sliders. Positions are a percentage of the screen, so they survive a
  resolution change. Elements anchored near an edge grow away from it, and the HUD clamps
  itself back on screen if a combination would overflow.
- **Twelve gauge shapes** - square, rounded, pill, circle, ring, radial, dot, bar, segment,
  diamond, hexagon, icon-only. One click to switch, per-gauge colours, warning thresholds
  with pulse.
- **Ten realistic speedometers** - minimal digital, classic dial, twin sport dials, digital
  cluster, luxury ring, JDM tachometer, American muscle, supercar, truck cluster, retro LCD.
  All with numbered graduations, real needles, a redline, and an E-F fuel gauge.
- **Compass and street names** - four compass styles (bar, tape, dial, text), street +
  cross street + district banner that can match the minimap width and sit on top of it.
- **Minimap control** - square or circle, movable, resizable, hideable, vehicle-only mode.
  Moves the real game minimap, so blips move with it.
- **Immersive mode** - the HUD fades out when nothing is happening and returns the moment
  anything moves. Compact mode, cinematic bars, HUD scale and opacity sliders.
- **Player-chosen refresh rate** - 30 / 60 / 90 fps, like qb-core's own setting.
- **Server policy** - lock any setting by dotted path, restrict the theme and speedometer
  lists, bound every slider, force settings per job or gang, push presets with `/hudadmin`.
- **Persistence** - KVP locally plus an optional database copy through oxmysql, so settings
  follow the character between machines.
- **Stress system** - server-authoritative, with the same events qb-hud used, so every
  stock qb resource keeps working unmodified.

## Compatibility

Everything below is detected at runtime and optional. Nothing is required.

| Capability | Detected |
|---|---|
| Framework | qb-core, qbx_core |
| Fuel | rcore_fuel (with range/litres), qb-fuel, LegacyFuel, ps-fuel, cdn-fuel, lc_fuel, x-fuel, okokGasStation, Renewed-Fuel, ox_fuel, native fallback |
| Voice | pma-voice, saltychat, mumble-voip |
| Notifications | qb-core, ox_lib, okokNotify, own themed toasts |
| Inventory (harness) | qb-inventory, ox_inventory, qs/ps/origen/codem/core |
| Mechanic / NOS | jim-mechanic (events + `hasnitro`/`noslevel` state bags), qb-mechanicjob, qb-tunerjob |
| Sounds | interact-sound |
| Storage | oxmysql (optional) |

Run `/hudinfo` in game to print what was actually detected.

## Installation

1. Drop `v-hud` into your `resources/` folder (any category folder works).
2. Stop `qb-hud` - move it out of `[qb]` or remove its `ensure`. Two HUDs fight over the
   minimap, the menu key and the `/cash` command. v-hud answers every event qb-hud handled,
   so no other resource needs editing.
3. `ensure v-hud` after `qb-core` (if the folder it sits in is already ensured, nothing to add).
4. Optional: `setr hud_locale "fr"` for French. It follows `qb_locale` otherwise.
5. Optional: install [oxmysql](https://github.com/overextended/oxmysql) and settings follow
   the character across machines. Without it, settings stay per machine. The table is
   created on first start; nothing to import.

There is no build step. Lua and JS ship as source.

## Usage

| Command | Effect |
|---|---|
| `I` or `/hud` or `/menu` | Open the settings menu |
| `/cinematic` | Toggle cinematic bars |
| `/hudreset` | Reset every setting to the server default |
| `/hudinfo` | Print detected framework, fuel, voice, inventory |
| `/cash`, `/bank` | Show a balance (answers even with the money element off) |
| `/hudadmin theme\|preset\|speedo\|reset\|list` | Admin: force settings on a player or everyone |

## Notifications

On a stock QBCore server, notifications belong to **qb-core**, not the HUD:
`QBCore.Functions.Notify` posts to qb-core's own NUI page. Stopping qb-hud removes no
notification, and installing v-hud restyles none of them. v-hud's own messages use themed
toasts (`Config.Notifications`). If you want *every* `QBCore:Notify` in the HUD's theme, set
`Config.Notifications.mirrorQbCore = true` **and** comment out the `SendNUIMessage` call in
`QBCore.Functions.Notify` (qb-core/client/functions.lua) - otherwise you get two
notifications per event. That edit is yours to make; this resource will not patch another
one silently.

## For developers

Exports (client): `GetSettings`, `SetSettings(patch)`, `OpenMenu`, `CloseMenu`, `IsMenuOpen`,
`Notify(msg, kind, ms)`, `AddStress(n)`, `RemoveStress(n)`, `GetNeeds()`, `GetLocation()`.
Exports (server): `AddStress(src, n)`, `RemoveStress(src, n)`, `SetStress(src, n)`,
`GetStress(src)`, `PushSettings(src, patch, msg)`, `ResetSettings(src)`.

Add a status gauge in `Config.Status` - it appears in the HUD, the element list and the
colour picker with no code change. Add a theme in `Config.ExtraThemes`. Every qb-hud event
(`hud:client:UpdateNeeds`, `UpdateStress`, `UpdateNitrous`, `OnMoneyChange`,
`hud:server:GainStress`, ...) is answered.

## Credits

Author: vyrriox

---

# v-hud (Version Française)

Un HUD entièrement personnalisable pour QBCore. Chaque joueur possède son HUD : chaque
élément se déplace à la souris, se recolore, change de forme, de taille, ou se désactive, et
le propriétaire du serveur décide lesquelles de ces libertés laisser ouvertes. Livré avec
cinq thèmes, douze formes de jauges, dix compteurs réalistes, quatre boussoles et un thème
par défaut en verre dépoli.

## Caractéristiques

- **Thème par défaut Clear Glass** - panneaux translucides avec un vrai flou d'arrière-plan,
  accent rose vif, palette Vice City. Quatre autres livrés avec : carré minimaliste, Miami,
  néon, modern.
- **Tout est déplaçable** - un éditeur par glisser-déposer avec grille aimantée, six
  dispositions prédéfinies, et des curseurs par élément. Les positions sont un pourcentage
  de l'écran : elles survivent à un changement de résolution. Un élément proche d'un bord
  grandit dans l'autre sens, et le HUD se recadre tout seul si une combinaison déborde.
- **Douze formes de jauges** - carré, arrondi, gélule, cercle, anneau, radial, pastille,
  barre, segments, losange, hexagone, icône seule. Un clic pour changer, couleur par jauge,
  seuils d'alerte avec pulsation.
- **Dix compteurs réalistes** - numérique minimal, cadran classique, double cadran sport,
  cluster numérique, anneau luxe, compte-tours JDM, muscle américaine, supercar, cadrans
  poids lourd, LCD rétro. Tous avec graduations chiffrées, vraies aiguilles, zone rouge et
  jauge d'essence E-F.
- **Boussole et noms de rue** - quatre styles de boussole (barre, ruban, cadran, texte),
  bandeau rue + rue transversale + quartier qui peut prendre la largeur de la minimap et se
  poser dessus.
- **Contrôle de la minimap** - carrée ou ronde, déplaçable, redimensionnable, masquable,
  mode véhicule uniquement. Déplace la vraie minimap du jeu : les blips suivent.
- **Mode immersif** - le HUD s'efface quand il ne se passe rien et revient dès que quelque
  chose bouge. Mode compact, bandes cinématiques, curseurs de taille et d'opacité.
- **Fréquence de rafraîchissement au choix** - 30 / 60 / 90 fps, comme le réglage de qb-core.
- **Politique serveur** - verrouiller n'importe quel réglage par chemin, restreindre les
  listes de thèmes et de compteurs, borner chaque curseur, imposer des réglages par métier
  ou gang, pousser des préréglages avec `/hudadmin`.
- **Persistance** - KVP local plus une copie optionnelle en base via oxmysql, pour que les
  réglages suivent le personnage d'une machine à l'autre.
- **Système de stress** - décidé côté serveur, avec les mêmes événements que qb-hud, donc
  toutes les ressources qb d'origine fonctionnent sans modification.

## Installation

1. Déposez `v-hud` dans votre dossier `resources/`.
2. Arrêtez `qb-hud` - deux HUD se battent pour la minimap, la touche du menu et `/cash`.
   v-hud répond à tous les événements que qb-hud gérait : aucune autre ressource à modifier.
3. `ensure v-hud` après `qb-core`.
4. Optionnel : `setr hud_locale "fr"` pour le français. Sinon il suit `qb_locale`.
5. Optionnel : installez [oxmysql](https://github.com/overextended/oxmysql) et les réglages
   suivent le personnage. Sans lui, ils restent par machine. La table se crée toute seule.

Pas d'étape de build. Le Lua et le JS sont livrés en source.

## Notifications

Sur un serveur QBCore d'origine, les notifications appartiennent à **qb-core**, pas au HUD :
`QBCore.Functions.Notify` écrit dans la page NUI de qb-core. Arrêter qb-hud n'enlève aucune
notification, et installer v-hud n'en restyle aucune. Les messages propres à v-hud passent
par des toasts thémés (`Config.Notifications`). Pour avoir *chaque* `QBCore:Notify` aux
couleurs du HUD : `Config.Notifications.mirrorQbCore = true` **et** commentez le
`SendNUIMessage` dans `QBCore.Functions.Notify` (qb-core/client/functions.lua), sinon chaque
événement donne deux notifications. Cette modification vous appartient ; cette ressource ne
touche pas une autre en silence.

## Credits

Author: vyrriox
