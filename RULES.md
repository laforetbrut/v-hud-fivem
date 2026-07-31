# Project Rules & AI/IDE Instructions

The single source of truth for anyone — human or assistant — working on this resource.
Read it before changing anything.

## 1. Project Identity

| Field | Value |
|---|---|
| Project name | v-hud |
| Resource name | `v-hud` |
| Version | Whatever `fxmanifest.lua` says. Do not restate it here. |
| Tech stack | Lua 5.4 (`lua54 'yes'`), vanilla JS + CSS for the NUI, optional MySQL via oxmysql |
| Author | vyrriox |
| Hard dependencies | **None.** That is a feature, defend it. |
| Optional, all runtime-detected | qb-core, qbx_core, oxmysql, rcore_fuel, qb-fuel/LegacyFuel/ps-fuel/cdn-fuel/lc_fuel/x-fuel/okokGasStation/Renewed-Fuel/ox_fuel, pma-voice, saltychat, mumble-voip, ox_lib, okokNotify, interact-sound, qb/ox/qs/ps/origen/codem/core inventories, jim-mechanic |

**The player owns the HUD; the server owns the policy.** Config.Defaults is what a player
starts with and may change; Config.Policy is what they may not. Every new setting must fit
that split, and every client payload goes through `Settings.normalise` before it is stored
or applied.

## 2. Git Workflow

- `main` is the only long-lived branch. Ordinary changes go straight to it.
- Feature branches `feat/<slug>`, fixes `fix/<slug>`, when a change wants review first.
- Commit messages: `type: lowercase summary` — `feat`, `fix`, `docs`, `perf`, `refactor`,
  `chore`. Present tense, no trailing full stop.
- **Never** put AI/assistant attribution in a commit, a comment, or any file.
- **Never** commit personal information. Git identity is the GitHub noreply address.
- **Never** commit `test-procedures/`, `.claude/`, `CLAUDE.md`, or `preview/` — gitignored.
- Releases are cut by the maintainer. A contributor never bumps the version.
- Release titles: `vX.Y.Z — Short subtitle`, subtitle from the first CHANGELOG bullet.

## 3. Code Conventions

**Language.** All code, comments and log lines in **English**. User-facing text goes in
`locales/en.lua` **and** `locales/fr.lua`, never inline. The two files must stay
key-for-key identical — `tools`-less: the check script enforces it.

**Naming.** Lua locals `camelCase`; the globals this resource defines are `HUD`, `Compat`,
`Bridge`, `Settings`, `Themes`, `Speedometers`, `Storage`, `State`, `Needs`, `Vehicle`,
`Minimap`, `Cinematic`, `Compass`, `Locales`, `L`. JS modules are `U`, `S`, `Status`,
`Speedo`, `Compass`, `Money`, `Toast`, `Layout`, `Menu`. Config keys: `PascalCase`
sections, `camelCase` fields. The database table is `vhud_settings`; events are
`vhud:side:Name`; qb-hud's `hud:*` names are answered for compatibility but never used for
anything new.

**Architecture rules.**
- Framework, fuel, voice, inventory and notify code lives in `bridge/`, behind a
  `Compat.*` (client) or `Bridge.*` (server) function with a `Config.Compat` entry. Never
  a resource name in a feature file.
- Never trust the client. Every NUI payload and every net event argument is re-validated
  server-side; `shared/settings.lua` is the single validator both sides call.
- A missing optional dependency degrades, never errors. Choose the fail direction on
  purpose and write it down: fuel fails OPEN (unreadable tank reads full), the harness
  item check fails CLOSED (no inventory, no ring).
- The NUI renders from data. Gauges come from `Config.Status`, themes from
  `shared/themes.lua` + `Config.ExtraThemes`, clusters from `shared/speedometers.lua`.
  Adding one must never require touching the update path.
- Send nothing to the NUI when nothing changed. The tick compares before it posts.

**NUI constraints that are not negotiable (all learned in game — see ERROR_LOG.md).**
- **No `backdrop-filter`.** CEF composites the page over the finished frame, so it samples
  nothing and paints solid black. Glass is a gradient plus a lit edge.
- **No `color-mix()`**, and nothing else newer than a 2022 Chromium (no `oklch`, `:has()`,
  container queries). An unsupported function invalidates the WHOLE declaration silently.
  Blends are computed with `U.mix()` and published as custom properties by state.js.
- **`os`, `io`, `package` are server-only.** The client uses `GetCloudTimeAsInt()` for wall
  clock.
- **NUI focus must always have a way out.** Every path that sets it clears it; there is a
  watchdog and `/hudunstuck`. Never early-return from a function that releases focus.
- **`IsNuiFocused()` is GLOBAL.** Read it to decide whether to TAKE focus (do not, if
  something else has it). Never to decide whether to RELEASE it — that steals the cursor
  from the multicharacter screen, the phone and the inventory. Track `State.focusHeld` and
  release only what this resource took.
- **Never `window.confirm`/`alert`/`prompt`.** They block the page with focus held.
- **NUI assets are cached by URL across a resource restart.** `html/index.html` writes its
  tags with a per-load token. Never replace them with plain `<link>`/`<script>` tags.

**Other gotchas already paid for.**
- An empty Lua list arrives in JS as `{}` — pass every list through `U.asArray`.
- Never write the `hidden` attribute through `U.attr`; use `U.show`.
- Player style values never feed UI surfaces the player is not styling
  (`--gauge-radius` vs `--radius`).
- The minimap is sized from screen HEIGHT: geometry is `vh`, never a percentage of the width.
  The native posY grows downward under 'B' alignment while CSS `bottom` grows upward.
- In a read-modify-write script over a source file, open for writing only after the new
  content is fully computed. Better: edit the file directly.

**What NOT to do.** No hard dependency. No placeholders or `TODO` in committed code. No
version bump unless asked. No emoji or em dashes in authored prose. No reformatting.

## 4. Project Structure

```
fxmanifest.lua          Manifest. THE version lives here. Files load in dependency order.
config.lua              Every operator knob, one file, heavily commented. 14 sections.
bridge/shared/hud.lua   `HUD`: merge/clamp/colour helpers, debug printer. Loads first.
bridge/shared/locale.lua`L(key)` and the locale table. English is the fallback.
bridge/client/compat.lua`Compat`: runtime detection of everything optional (client).
bridge/server/framework.lua `Bridge`: qb-core/qbx access, identifiers, permissions.
shared/themes.lua       The five themes as patches. Validated on both sides.
shared/speedometers.lua The ten clusters as data. The JS renderer is the other half.
shared/settings.lua     THE validator: merge, coerce, clamp, enforce policy.
client/settings.lua     `State`: boot, apply, save, NUI callbacks, exports.
client/minimap.lua      Native minimap control + cinematic bars.
client/compass.lua      Heading + street names, on their own slower loops.
client/vehicle.lua      Everything the cluster reads; fuel is cached per interval.
client/stress.lua       `Needs` (hunger/thirst/stress) + stress gain + screen effects.
client/main.lua         The tick. Diffs before it posts.
client/commands.lua     /hud, /cinematic, /hudreset, /hudinfo, the key mapping.
server/storage.lua      Optional oxmysql persistence. Off silently when absent.
server/main.lua         Boot payload, save/reset, /cash /bank, qb-hud callback shim.
server/stress.lua       Server-authoritative stress + exports.
server/admin.lua        /hudadmin + push/reset exports.
html/                   The NUI. js/util.js and js/state.js first; app.js routes messages.
locales/en.lua, fr.lua  Key-for-key identical, enforced by the check script.
tools/make-preview.py   Standalone browser preview built from the real files (lupa).
preview/                Generated. GITIGNORED — never commit.
```

## 5. Adding a New Feature (Step by Step)

1. Read `ERROR_LOG.md` and apply its prevention rules.
2. Add the `Config.<Feature>` knobs with comments explaining the *why* of each.
3. If a player can change it: add it to `Config.Defaults`, then to
   `Settings.sanitise` with the right coercion, then to the menu tab in `html/js/menu.js`,
   then both locale files.
4. Anything framework- or resource-touching goes in `bridge/` behind `Compat.*`/`Bridge.*`.
5. Server first (it owns every decision), then client, then NUI.
6. Run the checks in section 6. Regenerate the preview and look at it.
7. Update `CHANGELOG.md` (English then French) and `README.md` if the surface moved.

## 6. Testing Checklist

```bash
python <scratchpad>/check.py        # parses every .lua, locale parity, every L()/S.t()
                                    # key exists, manifest completeness, JS/Lua enum sync
python <scratchpad>/test_settings.py# 75 validator tests on a real Lua 5.4 (pip install lupa)
node --check html/js/*.js           # syntax on every NUI file
python tools/make-preview.py --lang fr   # then open preview/index.html and LOOK at it
```

- [ ] The overlap sweep (in the preview, see ERROR_LOG last entry) at 1280x720 AND 1080p.
- [ ] Hostile-input tests still pass: colours, enums, bounds, locked paths, unknown keys.
- [ ] Server console clean on boot; client F8 clean; `/hudinfo` names the right providers.
- [ ] Every optional dependency stopped: the HUD still boots and degrades as documented.
- [ ] Both locale files, every key, both ways.

## 7. Environment Setup

1. Clone into `resources/` (or junction a working copy, which is how the test server runs).
2. Nothing to build. `pip install luaparser lupa` for the checks, Node for `node --check`.
3. Test server: `server-test/` at the repo neighbour level — `db-start.bat`, then FXServer
   with the QBCore server.cfg. v-hud is junctioned into `[standalone]`; qb-hud is parked in
   `[disabled]`.

## 8. AI Assistant Instructions

1. **Read this file and `ERROR_LOG.md` first.** The gotchas in section 3 were each paid
   for once already.
2. **Never bump the version** unless explicitly asked.
3. **Never write personal information** anywhere. `vyrriox` is the only identity permitted.
4. **Never add AI attribution** to a commit, comment, or file.
5. **Both locale files, every time.** The check script will catch you; run it first.
6. **Never trust the client.** New settings go through `Settings.sanitise`; new events
   re-validate server-side.
7. **No new hard dependency, ever.** Detection goes in `Config.Compat` + `bridge/`.
8. **Test before reporting done.** Run section 6. Say explicitly what could not be
   verified — "the preview renders" is not "it works in game".
9. **Fix adjacent bugs you find**, log them in `ERROR_LOG.md` with a prevention rule.
