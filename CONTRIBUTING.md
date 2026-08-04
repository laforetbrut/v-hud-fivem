# Contributing to v-hud

Thanks for taking the time. This page is short on purpose — read it once and you know how the project
works.

## Where to go

| You want to... | Go to |
| --- | --- |
| Report something broken | [Bug report](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=01-bug.yml) |
| v-hud doesn't read your fuel / seatbelt / mechanic / inventory script | [Compatibility report](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=02-compatibility.yml) |
| Suggest a feature | [Feature request](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=03-feature.yml) |
| Fix the docs | [Documentation](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=04-docs.yml) |
| Ask a question, get setup help | [Discussions](https://github.com/laforetbrut/v-hud-fivem/discussions) |
| Report a vulnerability | [Privately](https://github.com/laforetbrut/v-hud-fivem/security/advisories/new) — never a public issue |

One rule for everything below: the [Code of Conduct](.github/CODE_OF_CONDUCT.md). It is short.

## Before you build your own thing

Three of the most common requests need no code at all:

- **Support a new fuel, seatbelt, mechanic or inventory script.** `Config.Compat` takes a resource
  name and an export, an event pair or a state bag. Nothing in Lua changes.
- **Stop a menu from hiding the HUD, or make one hide it.** `Config.HideWhen` does that per resource,
  and `onFocus = 'auto'` already handles most menus with no entry at all.
- **Add a gauge.** `Config.Status` is data. An entry gives you the gauge, its element switch and its
  colour picker.

[CONFIG.md](CONFIG.md) covers all three. If you end up patching Lua for one of these, that is a bug
in the config layer and worth an issue on its own.

## Two promises the code keeps

Anything that breaks these will not be merged, however good the rest of it is:

1. **Players can always move every element.** `positions` is never lockable.
2. **Players can always choose the minimap shape.** `minimap.shape` is never lockable.

They are enforced in `shared/settings.lua`, not merely documented — a config that tries to lock them
is refused and the server prints a warning.

## And one rule about other resources

v-hud never reaches into another resource. It asks a question that resource already answers, or
watches a signal it already publishes. A patch that edits somebody else's file, or that requires the
user to, is out of scope. A missing export must degrade quietly, never error.

## Working on the code

**Language.** Code, identifiers, comments, logs and commit messages in English. Documentation is
bilingual, English first, then French. Both locale files must carry the same keys — a string in one
and not the other is a bug, not a partial translation.

**Comments explain WHY.** The what is in the code. When a line exists because of a bug that was
actually hit, say so — those are the lines a future reader will otherwise "clean up".

**No version bumps in a pull request.** Releases are cut separately.

**No personal information anywhere.** Not in code, comments, commit messages or screenshots: no email
addresses, real names, identifiers, IP addresses, keys or local file paths.

### Things this codebase has learned the hard way

You will save yourself an evening by knowing these before you touch the NUI:

- **FiveM's CEF is Chromium ~90–103.** No `backdrop-filter` — it composites over the finished frame
  and renders as a solid black box. No `color-mix()`, `oklch()`, `:has()`, container queries. Its UA
  stylesheet puts `align-items: flex-start` on every `<button>`, which is why the menu cards are
  `div` with `role="button"`.
- **A browser is not a proxy for CEF.** When a page is right in Chrome and wrong in game, suspect a
  UA-stylesheet or feature difference before suspecting your own logic — and reproduce it by
  injecting the old rule into the test harness.
- **CEF caches NUI assets by URL and does not drop them on `restart`.** Stylesheets and scripts carry
  a per-load token; `html/index.html` cannot, so a change to that file needs a game-client restart.
- **`os`, `io` and `package` are server-only** in FiveM Lua. The client uses `GetCloudTimeAsInt()`.
- **Cfx BOOL out-parameters come back as `true` on some builds and `1` on others.** Test both, and
  count a native's return values before destructuring — `pcall` prepends its own.

### Verifying

Not "it works". Before opening a pull request:

- Every Lua file compiles. Note that Lua's `load()` returns `nil, message` on failure — a checker
  written as `if load(src) is None` passes every broken file. Test the boolean Lua returns.
- `node --check` on every JavaScript file you touched.
- Both locale files still have identical keys.
- Tested in game, on a real server, in the situation the change is about.

**If you fixed a bug, confirm your test FAILS on the old code.** A test that passes both ways proves
nothing. This is the single habit that has caught the most in this project.

## Pull requests

One change per pull request. A fix and a refactor in the same diff means the fix cannot be reviewed
and cannot be reverted on its own.

Say what the **root cause** was, not just the symptom. That reasoning is what stops the bug coming
back, and it is what goes in `ERROR_LOG.md`.

Screenshots for anything visual, before and after.

---

# Contribuer à v-hud (Version Française)

Merci d'y consacrer du temps. Cette page est courte volontairement : lisez-la une fois et vous savez
comment le projet fonctionne.

## Où aller

| Vous voulez... | Allez à |
| --- | --- |
| Signaler un problème | [Rapport de bug](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=01-bug.yml) |
| v-hud ne lit pas votre script de carburant / ceinture / mécanique / inventaire | [Compatibilité](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=02-compatibility.yml) |
| Proposer une fonctionnalité | [Demande de fonctionnalité](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=03-feature.yml) |
| Corriger la documentation | [Documentation](https://github.com/laforetbrut/v-hud-fivem/issues/new?template=04-docs.yml) |
| Poser une question, obtenir de l'aide | [Discussions](https://github.com/laforetbrut/v-hud-fivem/discussions) |
| Signaler une faille | [En privé](https://github.com/laforetbrut/v-hud-fivem/security/advisories/new) — jamais en issue publique |

Une règle pour tout ce qui suit : le [Code de conduite](.github/CODE_OF_CONDUCT.md). Il est court.

## Avant de coder quoi que ce soit

Trois des demandes les plus fréquentes ne demandent aucun code :

- **Prendre en charge un nouveau script de carburant, ceinture, mécanique ou inventaire.**
  `Config.Compat` prend un nom de ressource et un export, une paire d'événements ou un state bag.
- **Empêcher un menu de cacher le HUD, ou l'y forcer.** `Config.HideWhen` le fait par ressource, et
  `onFocus = 'auto'` gère déjà la plupart des menus sans aucune entrée.
- **Ajouter une jauge.** `Config.Status` est de la donnée. Une entrée vous donne la jauge, son
  interrupteur et son sélecteur de couleur.

[CONFIG.md](CONFIG.md) couvre les trois. Si vous finissez par patcher du Lua pour l'un d'eux, c'est un
bug de la couche de configuration et cela mérite une issue à part entière.

## Deux promesses que le code tient

Tout ce qui les enfreint ne sera pas fusionné, quelle que soit la qualité du reste :

1. **Les joueurs peuvent toujours déplacer chaque élément.** `positions` n'est jamais verrouillable.
2. **Les joueurs peuvent toujours choisir la forme de la minimap.** `minimap.shape` non plus.

Elles sont garanties dans `shared/settings.lua`, pas seulement documentées : une config qui tente de
les verrouiller est refusée et le serveur affiche un avertissement.

## Et une règle sur les autres ressources

v-hud ne touche jamais à une autre ressource. Il pose une question qu'elle répond déjà, ou observe un
signal qu'elle publie déjà. Un patch qui modifie le fichier d'autrui, ou qui demande à l'utilisateur
de le faire, est hors sujet. Un export absent doit se dégrader silencieusement, jamais lever.

## Travailler sur le code

**Langue.** Code, identifiants, commentaires, logs et messages de commit en anglais. La documentation
est bilingue, anglais d'abord puis français. Les deux fichiers de locale doivent porter les mêmes
clés : une chaîne dans l'un et pas dans l'autre est un bug, pas une traduction partielle.

**Les commentaires expliquent POURQUOI.** Le quoi est dans le code. Quand une ligne existe à cause
d'un bug réellement rencontré, dites-le : ce sont les lignes qu'un lecteur futur « nettoiera » sinon.

**Pas de changement de version dans une pull request.** Les versions sont publiées séparément.

**Aucune information personnelle nulle part.** Ni dans le code, ni les commentaires, ni les messages
de commit, ni les captures : pas d'adresse e-mail, de nom réel, d'identifiant, d'adresse IP, de clé ni
de chemin local.

### Ce que ce code a appris à ses dépens

Vous vous épargnerez une soirée en connaissant ceci avant de toucher au NUI :

- **Le CEF de FiveM est un Chromium ~90-103.** Pas de `backdrop-filter` : il compose par-dessus
  l'image finie et rend un carré noir opaque. Pas de `color-mix()`, `oklch()`, `:has()`, container
  queries. Sa feuille de style UA pose `align-items: flex-start` sur chaque `<button>`, d'où les
  cartes du menu en `div` avec `role="button"`.
- **Un navigateur ne remplace pas le CEF.** Quand une page est correcte dans Chrome et fausse en jeu,
  soupçonnez une différence de feuille UA ou de fonctionnalité avant votre propre logique — et
  reproduisez-la en injectant l'ancienne règle dans votre banc d'essai.
- **Le CEF met les fichiers NUI en cache par URL et ne les libère pas au `restart`.** Les feuilles de
  style et les scripts portent un jeton par chargement ; `html/index.html` ne le peut pas, donc une
  modification de ce fichier demande un redémarrage du client.
- **`os`, `io` et `package` sont réservés au serveur** en Lua FiveM. Le client utilise
  `GetCloudTimeAsInt()`.
- **Les sorties BOOL des natifs Cfx valent `true` sur certains builds et `1` sur d'autres.** Testez
  les deux, et comptez les valeurs de retour d'un natif avant de destructurer : `pcall` en ajoute une.

### Vérifier

Pas « ça marche ». Avant d'ouvrir une pull request :

- Tous les fichiers Lua compilent. Attention : `load()` renvoie `nil, message` en cas d'échec — un
  contrôle écrit `if load(src) is None` laisse passer tous les fichiers cassés. Testez le booléen que
  Lua renvoie.
- `node --check` sur chaque fichier JavaScript touché.
- Les deux fichiers de locale ont toujours des clés identiques.
- Testé en jeu, sur un vrai serveur, dans la situation que le changement concerne.

**Si vous corrigez un bug, vérifiez que votre test ÉCHOUE sur l'ancien code.** Un test qui passe dans
les deux cas ne prouve rien. C'est l'habitude qui a attrapé le plus de choses dans ce projet.

## Pull requests

Un changement par pull request. Un correctif et un remaniement dans le même diff, c'est un correctif
qu'on ne peut ni relire ni annuler séparément.

Dites quelle était la **cause racine**, pas seulement le symptôme. C'est ce raisonnement qui empêche
le bug de revenir, et c'est ce qui va dans `ERROR_LOG.md`.

Des captures pour tout ce qui est visuel, avant et après.
