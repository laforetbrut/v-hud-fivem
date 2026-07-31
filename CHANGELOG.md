# Changelog

All notable changes to v-hud are documented here.

---

## [1.0.0] - 2026-07-31

### Added

- **Clear Glass default theme** — Translucent panels built from a layered gradient, a lit
  edge and a drop shadow rather than `backdrop-filter`, which FiveM's CEF composites over
  the finished frame and renders as a solid black box. Hot pink accent, Vice City palette. Four more themes ship alongside: square minimalist,
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
- **Belt and door chimes** — Two distinct frontend sounds above a configurable speed, each
  with its own grace period and repeat interval, so a door nudged at a junction does not
  beep. Uses the game's own samples, so no sound resource is required. The bonnet and boot
  are excluded by default: a mechanic script leaves the bonnet up, and that is not a
  driving fault. See `Config.Alerts`.

- **Stomach growl** — A low rumble when hunger or thirst crosses down through 10%, 5% and 0%.
  Edge-triggered, so sitting at 4% is silent and climbing back up never fires. Synthesised by
  the NUI page with Web Audio rather than streamed, so there is no audio file to ship and the
  length is an exact cap. Configurable in `Config.Alerts.growl`.

- **Full dashboard tell-tales** — Twenty-one warning lamps drawn as the symbols a real
  cluster uses, so none of them need a legend: dipped beam with its rays slanting down and main
  beam with them straight, solid triangles for the indicators, handbrake, low fuel, seatbelt,
  door, bonnet, engine, cruise, nitrous and harness. Lamp colours are fixed rather than themed —
  a main-beam lamp is blue in every car ever built, and a pink low-fuel light means nothing to
  anybody. Sized to be read from a driving seat: 38x32 with a 23px glyph, and the unlit state
  carries enough contrast to be identified before it comes on.
- **Mechanical warning lamps** — Brakes, coolant, injector, battery, clutch, transmission,
  axle and suspension, read from whichever mechanic script is installed. Vehicle state bags
  first, then a plate-keyed framework callback; qb-mechanicjob's is wired up by default and was
  checked against an installed copy. Each lamp appears only when that part is worn, and a
  server with no mechanic script shows none of them. Configured in `Config.Compat.partBags` /
  `partsCallback`, and the player can turn the whole set off.
- **Stale-page detector** — FiveM's CEF caches NUI pages by URL and does not drop them on
  `restart`. The stylesheets and scripts already work around that with a per-load token, but
  `index.html` itself cannot, so a change to it can be invisible until the game client is
  restarted — silently, with no symptom. The page now checks that every module it expects
  actually loaded and prints what is missing and what to do about it.

### Fixed

- **Blank speedometer cards in the settings menu** — Two independent causes. The preview
  faces were built and painted before being inserted into the page, and `getTotalLength()`
  returns 0 for a path that is not in the document; the zero was cached, so every arc gave up
  permanently. And the cards were `<button>` elements: the UA stylesheet Chromium ships up to
  and including 103 — which is what FiveM's CEF is — sets `align-items: flex-start` on every
  button, so in a column card each child is sized to its own content. The preview frame's only
  child was absolutely positioned, giving the frame a max-content width of zero, and
  `overflow: hidden` clipped the instrument away entirely. Chrome dropped that UA rule years
  ago, which is why the same page was perfect in a browser and blank in game. The cards are
  now `div`s, the face stays in normal flow and is scaled by a transform, and zero lengths are
  never cached. The same button bug was collapsing the theme colour swatches to a 26px sliver.
- **Minimap showed the wrong view after being moved** — `SetMinimapComponentPosition` updates
  `minimap_mask` and `minimap_blur` live, but the `minimap` component only re-reads its
  rectangle when the map is rebuilt. The rebuild was gated on a change of *shape*, so moving
  or resizing the map moved the hole, the blur and the CSS border and left the terrain and the
  player blip behind. It is now gated on the whole geometry, and the rebuild wait dropped from
  50ms to a single frame so it is no longer a visible jump.
- **Minimap border left on screen with the minimap off** — The border followed only
  `minimap.hide`, not the element toggle, vehicle-only mode, cinematic mode or another
  resource's menu. It now follows the same decision as the radar itself.
- **Panel plates behind the dial clusters** — The sport, truck and muscle faces were drawn on
  a translucent backing box. Instruments made of dials float over the scene now; the plate is
  kept only for the faces that genuinely are a panel — the minimal readout, the digital
  cluster and the LCD.
- **Readouts covering the dials** — The odometer badge was the widest item inside the centre
  plate, which made the plate 99px across a 168px dial and hid the first and last numerals of
  the scale. It hangs below the plate now. The fuel strip on the supercar face carried
  `flex: 1` and grew to 204px tall on a 244px face with the speed printed inside it. Verified
  by measurement across all ten faces at three speeds: no overlaps, nothing escaping a face.
- **Warning tell-tales too small to read** — 24x20 with a 13px glyph made a row of indistinct
  smudges. Now 38x32 with a 23px glyph, a heavier stroke, and an unlit state with enough
  contrast to be identified before the lamp comes on.
- **Door chime removed by default** — A door that reads as open is usually a broken door, and
  a chime the player cannot silence by driving properly is one that trains them to ignore
  every other warning.
- **Chrome bezel could unpaint itself** — `url(#chromeGradient)` resolves against the whole
  document, and each built face declared its own copy of that id. A tab change that deleted
  the winning copy took the live cluster's bezel with it. The gradient is now declared once,
  in a node nothing removes.
- **HUD drawn over the quit prompt** — `IsPauseMenuActive()` is false for the Alt+F4
  confirmation, which is a frontend warning screen with the pause menu already closed
  behind it. Warning screens and the character-switch fly-over are now checked too.
- **Street banner clipped by the gauge arc on a round map** — Six gauges on an arc need
  more height than the map has, so the overshoot is now tilted downward as far as the
  screen allows and the banner is lifted by exactly what is left, measured rather than
  guessed. Square and wide maps are unchanged.

- **Headlight tell-tales never changed** — `GET_VEHICLE_LIGHTS_STATE` returns three values,
  and `pcall` adds a fourth in front. Destructuring only three meant `lightsOn` held the
  native's return value, `highBeams` held the real `lightsOn`, and the real high-beam state was
  discarded. Both were then compared with `== 1`, and Cfx hands these back as `true` on some
  builds — so on those, neither lamp could light at all. Fixed, and covered by a regression
  test that stubs the native in both shapes.
- **Engine lamp lit with the engine off** — It was driven by engine HEALTH, not by whether the
  engine is running, so a switched-off car in good condition sat there green. Green now means
  running and healthy, red means damaged, dark means off.

### Ajouts

- **Thème par défaut Clear Glass** — Panneaux translucides composés d'un dégradé en couches,
  d'une arête éclairée et d'une ombre portée plutôt que de `backdrop-filter`, que le CEF de
  FiveM compose par-dessus l'image finie et rend en carré noir. Accent rose vif, palette
  Vice City. Quatre autres thèmes livrés :
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
- **Alertes ceinture et porte** — Deux sons distincts au-delà d'une vitesse configurable,
  chacun avec son délai de tolérance et son intervalle de répétition : une porte effleurée
  à un carrefour ne déclenche rien. Utilise les sons du jeu, donc aucune ressource audio
  n'est requise. Capot et coffre sont exclus par défaut : un script de mécanique laisse le
  capot ouvert, et ce n'est pas une faute de conduite. Voir `Config.Alerts`.

- **Gargouillement d'estomac** — Un grondement grave quand la faim ou la soif descend sous
  10 %, 5 % et 0 %. Déclenché sur le franchissement : rester à 4 % est silencieux et remonter
  ne déclenche jamais. Synthétisé par la page NUI en Web Audio plutôt que streamé : aucun
  fichier audio à livrer et la durée est une borne exacte. Réglable dans `Config.Alerts.growl`.

- **Témoins de bord complets** — Vingt et un témoins dessinés avec les symboles d'un vrai
  tableau de bord, donc aucun n'a besoin de légende : feux de croisement aux rayons inclinés,
  pleins phares aux rayons droits, triangles pleins pour les clignotants, frein à main, réserve
  de carburant, ceinture, porte, capot, moteur, régulateur, nitro et harnais. Les couleurs sont
  fixes et non thématisées : un témoin de pleins phares est bleu dans toutes les voitures du
  monde, et une réserve de carburant rose ne veut rien dire. Dimensionnés pour être lus depuis
  le siège conducteur : 38x32 avec un pictogramme de 23 px, et l'état éteint garde assez de
  contraste pour être identifié avant de s'allumer.
- **Témoins mécaniques** — Freins, refroidissement, injecteur, batterie, embrayage, boîte,
  transmission et suspension, lus depuis le script de mécanique installé. State bags du
  véhicule d'abord, puis un callback serveur indexé sur la plaque ; celui de qb-mechanicjob est
  câblé par défaut et a été vérifié sur une copie installée. Chaque témoin n'apparaît que si la
  pièce est usée, et un serveur sans script de mécanique n'en affiche aucun. Réglable dans
  `Config.Compat.partBags` / `partsCallback`, et le joueur peut tout désactiver.
- **Détection de page périmée** — Le CEF de FiveM met les pages NUI en cache par URL et ne les
  libère pas au `restart`. Les feuilles de style et les scripts contournent déjà cela avec un
  jeton par chargement, mais `index.html` lui-même ne le peut pas : une modification de ce
  fichier peut rester invisible jusqu'au redémarrage du client, silencieusement et sans
  symptôme. La page vérifie désormais que tous ses modules ont bien été chargés et signale ce
  qui manque ainsi que la marche à suivre.

### Correctifs

- **Cartes de compteur vides dans le menu** — Deux causes indépendantes. Les aperçus étaient
  construits et peints avant d'être insérés dans la page, or `getTotalLength()` renvoie 0 pour
  un tracé absent du document, et ce zéro était mis en cache : chaque arc abandonnait
  définitivement. Et les cartes étaient des `<button>` : la feuille de style UA livrée par
  Chromium jusqu'à la version 103 incluse, qui est celle du CEF de FiveM, pose
  `align-items: flex-start` sur tout bouton, donc dans une carte en colonne chaque enfant est
  dimensionné à son propre contenu. L'unique enfant du cadre d'aperçu était en positionnement
  absolu, donc le cadre avait une largeur de contenu nulle, et `overflow: hidden` découpait
  l'instrument entier. Chrome a supprimé cette règle UA il y a des années : d'où une page
  parfaite dans un navigateur et vide en jeu. Les cartes sont désormais des `div`, l'instrument
  reste dans le flux et n'est que mis à l'échelle, et un zéro n'est plus mis en cache. Le même
  bug de bouton réduisait les pastilles de couleur des thèmes à un filet de 26 px.
- **Minimap affichant la mauvaise vue après déplacement** — `SetMinimapComponentPosition` met
  à jour `minimap_mask` et `minimap_blur` en direct, mais le composant `minimap` ne relit son
  rectangle qu'à une reconstruction de la carte. Cette reconstruction était conditionnée à un
  changement de *forme* : déplacer ou redimensionner la carte déplaçait le trou, le flou et la
  bordure CSS en laissant le terrain et le curseur du joueur derrière. Elle dépend maintenant
  de toute la géométrie, et l'attente est passée de 50 ms à une seule image, donc elle n'est
  plus visible.
- **Bordure de minimap restée à l'écran minimap désactivée** — La bordure ne suivait que
  `minimap.hide`, pas le réglage d'élément, le mode véhicule uniquement, le mode cinématique
  ni le menu d'une autre ressource. Elle suit désormais la même décision que le radar.
- **Plateaux derrière les compteurs à cadrans** — Les faces sport, poids lourd et muscle
  étaient posées sur une boîte translucide. Un instrument fait de cadrans flotte désormais sur
  la scène ; le plateau n'est gardé que pour les faces qui sont réellement un panneau : le
  bloc numérique minimal, le cluster numérique et l'afficheur LCD.
- **Lectures recouvrant les cadrans** — Le badge d'odomètre était l'élément le plus large du
  plateau central, ce qui portait celui-ci à 99 px sur un cadran de 168 px et masquait le
  premier et le dernier chiffre de l'échelle. Il pend maintenant sous le plateau. La jauge de
  carburant de la face supercar portait `flex: 1` et s'étirait à 204 px de haut sur une face de
  244 px, avec la vitesse imprimée dedans. Vérifié par mesure sur les dix faces à trois
  vitesses : aucun chevauchement, rien qui déborde.
- **Témoins d'alerte illisibles** — 24x20 avec un pictogramme de 13 px donnait une rangée de
  taches indistinctes. Désormais 38x32 avec un pictogramme de 23 px, un trait plus épais et un
  état éteint assez contrasté pour être identifié avant que le témoin s'allume.
- **Alerte sonore de porte retirée par défaut** — Une porte signalée ouverte est le plus
  souvent une porte cassée, et une alerte qu'on ne peut pas faire taire en conduisant
  correctement apprend à ignorer toutes les autres.
- **Le cerclage chromé pouvait s'effacer** — `url(#chromeGradient)` se résout à l'échelle du
  document entier, et chaque instrument construit déclarait sa propre copie de cet
  identifiant. Un changement d'onglet supprimant la copie gagnante emportait le cerclage du
  compteur en jeu. Le dégradé est maintenant déclaré une seule fois, dans un nœud que rien
  ne supprime.
- **HUD affiché par-dessus la fenêtre de fermeture** — `IsPauseMenuActive()` est faux pour la
  confirmation Alt+F4 : c'est un écran d'avertissement, le menu pause étant déjà refermé
  derrière. Les écrans d'avertissement et le survol de changement de personnage sont
  désormais pris en compte.
- **Nom de rue rogné par l'arc de jauges sur carte ronde** — Six jauges en arc demandent plus
  de hauteur que la carte n'en occupe ; le dépassement est maintenant basculé vers le bas
  autant que l'écran le permet, et le bandeau est relevé d'exactement ce qui reste, mesuré
  et non estimé. Les cartes carrées et larges sont inchangées.
- **Témoins de phares figés** — `GET_VEHICLE_LIGHTS_STATE` renvoie trois valeurs, et `pcall`
  en ajoute une quatrième devant. N'en destructurer que trois faisait que `lightsOn` contenait
  la valeur de retour du natif, `highBeams` contenait le vrai `lightsOn`, et l'état réel des
  pleins phares était jeté. Les deux étaient ensuite comparés à `== 1`, or Cfx les renvoie en
  `true` sur certains builds : sur ceux-là, aucun témoin ne pouvait s'allumer. Corrigé, avec un
  test de non-régression qui simule le natif dans les deux formes.
- **Témoin moteur allumé moteur coupé** — Il était piloté par la SANTÉ du moteur, pas par son
  état de marche : une voiture éteinte en bon état restait au vert. Vert signifie désormais en
  marche et en bon état, rouge endommagé, éteint coupé.

---
