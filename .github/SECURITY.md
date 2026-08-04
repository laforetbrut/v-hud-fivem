# Security Policy

## Supported versions

Only the latest release receives fixes. Update before reporting.

| Version | Supported |
| ------- | --------- |
| 1.0.1   | Yes       |
| < 1.0.1 | No        |

## Reporting a vulnerability

**Do not open a public issue for a security problem.** A HUD accepts a settings payload from every
client and writes it to the server's database, and it holds the policy that decides what players may
and may not change. A public report is an exploit handed to every server running it.

Use GitHub's private reporting instead:
**[Report a vulnerability](https://github.com/laforetbrut/v-hud-fivem/security/advisories/new)**

Please include the version, the framework, what an attacker can do, and the steps. A proof of concept
against your own test server is welcome; do not test against a server you do not own.

You will get a first answer within a few days. A fix ships in the next release, and the advisory is
published once servers have had time to update.

## What counts as a vulnerability here

Worth reporting:

- A crafted NUI payload that writes a value `Config.Policy` was configured to refuse.
- Anything a client can send that errors the server, hangs it, or drives unbounded database work.
- A way for one player's settings to reach another player's account.
- A permission check on `/hudadmin` that can be skipped.

Not a vulnerability, and an ordinary issue instead:

- A player changing their own HUD in a way you dislike but did not restrict.
- Anything that needs server console access, or an already-compromised server, to exploit.

---

# Politique de sécurité (Version Française)

## Versions prises en charge

Seule la dernière version reçoit des correctifs. Mettez à jour avant de signaler.

| Version | Prise en charge |
| ------- | --------------- |
| 1.0.1   | Oui             |
| < 1.0.1 | Non             |

## Signaler une faille

**N'ouvrez pas d'issue publique pour un problème de sécurité.** Un HUD accepte une charge de réglages
de chaque client et l'écrit dans la base du serveur, et il porte la politique qui décide de ce que les
joueurs peuvent changer. Un rapport public est un exploit offert à tous les serveurs concernés.

Utilisez le signalement privé de GitHub :
**[Signaler une faille](https://github.com/laforetbrut/v-hud-fivem/security/advisories/new)**

Indiquez la version, le framework, ce qu'un attaquant peut faire et les étapes. Une preuve de concept
contre votre propre serveur de test est bienvenue ; ne testez pas contre un serveur qui ne vous
appartient pas.

Vous aurez une première réponse sous quelques jours. Le correctif part dans la version suivante, et
l'avis est publié une fois que les serveurs ont eu le temps de mettre à jour.
