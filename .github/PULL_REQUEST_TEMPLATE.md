# What this changes / Ce que ça change

<!-- One or two sentences. What was wrong, or what is new. -->
<!-- Une ou deux phrases. Ce qui n'allait pas, ou ce qui est nouveau. -->

Closes #

## Why / Pourquoi

<!-- The reasoning, not the diff. If it fixes a bug, say what the ROOT CAUSE was - not just the
     symptom. That reasoning is what stops the bug coming back. -->
<!-- Le raisonnement, pas le diff. Si c'est un correctif, dites quelle était la CAUSE RACINE,
     pas seulement le symptôme. C'est ce raisonnement qui empêche le bug de revenir. -->

## How it was verified / Comment ça a été vérifié

<!-- Not "it works". What did you actually run or observe? -->
<!-- Pas "ça marche". Qu'avez-vous réellement lancé ou observé ? -->

- [ ] Tested in game on a real server / Testé en jeu sur un vrai serveur
- [ ] Every Lua file still compiles / Tous les fichiers Lua compilent encore
- [ ] Every JS file passes `node --check` / Tous les fichiers JS passent `node --check`
- [ ] Both locale files still have the same keys / Les deux fichiers de locale ont toujours les mêmes clés

**If this fixes a bug:** did you confirm your test FAILS on the old code? A test that passes both
ways proves nothing.
**Si c'est un correctif :** avez-vous confirmé que votre test ÉCHOUE sur l'ancien code ? Un test qui
passe dans les deux cas ne prouve rien.

## Checklist

- [ ] No personal information anywhere: no email addresses, real names, IDs, IP addresses, keys or
      local file paths, in the code, the comments or the commit messages.
      / Aucune information personnelle : ni adresse e-mail, ni nom réel, ni identifiant, ni adresse
      IP, ni clé, ni chemin local, dans le code, les commentaires ou les messages de commit.
- [ ] Documentation is bilingual, English then French, wherever I touched it.
      / La documentation est bilingue, anglais puis français, partout où j'y ai touché.
- [ ] I did not bump the version. Releases are cut separately.
      / Je n'ai pas changé le numéro de version. Les versions sont publiées séparément.
- [ ] Players can still move every element and choose the minimap shape.
      / Les joueurs peuvent toujours déplacer chaque élément et choisir la forme de la minimap.
- [ ] This resource still reaches into no other resource.
      / Cette ressource ne touche toujours à aucune autre ressource.

## Screenshots / Captures

<!-- For anything visual, before and after. / Pour tout ce qui est visuel, avant et après. -->
