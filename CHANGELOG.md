# Changelog

All notable changes to v-hud are documented here.

---

## [1.0.0] - 2026-07-31

### Added

- **Clear Glass default theme** — Translucent panels with a real backdrop blur, hot pink
  accent and a Vice City palette. Four more themes ship alongside: square minimalist,
  Miami, neon and modern, each choosing its own gauge shape, surface, speedometer and
  compass. A theme is a patch: applying one never touches the player's layout.
- **Full player customisation** — Drag editor with snap-to-grid, six layout presets,
  per-element position sliders, twelve gauge shapes, four panel surfaces (glass, tint,
  solid, none) with an adjustable blur, per-gauge colours, scale, opacity, compact mode,
  immersive fade-out and cinematic bars. Every setting is validated server-side before it
  is stored.
- **Ten realistic instrument clusters** — Minimal digital, classic dial, twin sport dials,
  digital cluster, luxury ring, JDM tachometer, American muscle three-gauge panel,
  supercar shift-light ring, truck cluster and retro LCD bar graph. All share one dial
  builder: numbered graduations, real needle sweeps, a redline and an E-F fuel strip.
- **Dual-axis anchoring** — Every element records which of its edges its position refers
  to, so elements near the bottom grow upward and elements near the right stay pinned
  there. A post-render clamp nudges anything that would still overflow back on screen,
  verified by an automated sweep of 240 theme/shape/cluster/layout combinations at two
  resolutions.
- **Server policy** — Lockable settings by dotted path, restrictable theme and
  speedometer lists, bounded sliders, per-job and per-gang overrides applied without
  touching the player's saved settings, admin presets and `/hudadmin`.
- **Runtime compatibility layer** — Detects qb-core/qbx_core, eleven fuel resources
  (rcore_fuel first, with range and litres readouts), three voice resources, seven
  inventories, jim-mechanic NOS via events and `hasnitro`/`noslevel` state bags, and
  interact-sound. Every qb-hud event is answered so stock qb resources work unmodified.
- **Persistence** — Per-character KVP plus an optional oxmysql copy with
  newest-wins merging, debounced saves and a flush on disconnect.
- **Player-chosen refresh rate** — 30, 60 or 90 fps, configurable per server.
- **Bilingual locales** — English and French, key-for-key identical, with a static check
  enforcing parity.

### Ajouts

- **Thème par défaut Clear Glass** — Panneaux translucides avec un vrai flou
  d'arrière-plan, accent rose vif et palette Vice City. Quatre autres thèmes livrés :
  carré minimaliste, Miami, néon et modern, chacun avec sa forme de jauges, sa surface,
  son compteur et sa boussole. Un thème est un correctif : l'appliquer ne touche jamais la
  disposition du joueur.
- **Personnalisation complète par le joueur** — Éditeur par glisser-déposer avec grille
  aimantée, six dispositions prédéfinies, curseurs de position par élément, douze formes
  de jauges, quatre surfaces de panneaux (verre, teinte, opaque, aucune) avec flou
  réglable, couleurs par jauge, taille, opacité, mode compact, effacement immersif et
  bandes cinématiques. Chaque réglage est validé côté serveur avant d'être stocké.
- **Dix compteurs réalistes** — Numérique minimal, cadran classique, double cadran sport,
  cluster numérique, anneau luxe, compte-tours JDM, panneau trois cadrans muscle
  américaine, anneau à témoins supercar, cadrans poids lourd et LCD rétro. Tous partagent
  un même constructeur de cadran : graduations chiffrées, vraies aiguilles, zone rouge et
  jauge d'essence E-F.
- **Ancrage sur les deux axes** — Chaque élément retient à quel bord sa position se
  réfère : un élément en bas grandit vers le haut, un élément à droite y reste épinglé.
  Un recadrage après rendu ramène à l'écran ce qui déborderait encore, vérifié par un
  balayage automatisé de 240 combinaisons thème/forme/compteur/disposition à deux
  résolutions.
- **Politique serveur** — Réglages verrouillables par chemin, listes de thèmes et de
  compteurs restreignables, curseurs bornés, surcharges par métier et par gang appliquées
  sans toucher aux réglages sauvegardés du joueur, préréglages admin et `/hudadmin`.
- **Couche de compatibilité à l'exécution** — Détecte qb-core/qbx_core, onze ressources de
  carburant (rcore_fuel en premier, avec autonomie et litres), trois ressources vocales,
  sept inventaires, la NOS de jim-mechanic par événements et state bags
  `hasnitro`/`noslevel`, et interact-sound. Chaque événement qb-hud reçoit une réponse :
  les ressources qb d'origine fonctionnent sans modification.
- **Persistance** — KVP par personnage plus une copie oxmysql optionnelle, fusion au plus
  récent, sauvegardes différées et vidage à la déconnexion.
- **Fréquence de rafraîchissement au choix** — 30, 60 ou 90 fps, configurable par serveur.
- **Locales bilingues** — Anglais et français, identiques clef pour clef, avec un contrôle
  statique qui impose la parité.

---
