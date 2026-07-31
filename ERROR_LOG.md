# Error Log

Problems hit while building v-hud, their root causes, and the rule that stops each one from
happening again. Read the relevant entries before working in the same area.

---

## [2026-07-31 — build] — Empty Lua table encodes as `{}` and breaks every JS array method

**Context:** Opening the settings menu with the shipped (empty) `Config.Policy.locked` list.
**Error:** `TypeError: state.locked.some is not a function` — the menu opened with all ten
tabs and no content in any of them.
**Root cause:** An empty Lua table carries no hint whether it was a list or a map, and
`json.encode` writes it as `{}`. The NUI received an object where it expected an array, and
the first `.some()` threw. Worse, the default config ships `locked` empty, so this broke
every fresh install while testing with a non-empty list worked.
**Fix:** `U.asArray()` in html/js/util.js, applied to every list in the boot payload at the
single point of entry (`S.boot`), plus a guard in `isLocked`.
**Prevention:** Any Lua table that is a LIST and can be empty must pass through `U.asArray`
on the JS side. Test the empty case, not only the populated one — the empty case is the
shipped default.

## [2026-07-31 — build] — `hidden="false"` still hides the element

**Context:** The vehicle-extras chips (dev marker, parachute) were visible on spawn for
players who are not developers, and chips never reappeared once hidden.
**Error:** No console error — the wrong elements were simply visible or stuck invisible.
**Root cause:** `hidden` is an HTML boolean attribute: its PRESENCE hides the element,
whatever its value. `U.attr(node, 'hidden', false)` writes `hidden="false"`, which hides
just as firmly as `hidden="true"`.
**Fix:** `U.show(node, visible)` which adds or REMOVES the attribute, used everywhere a
visibility toggle was going through `U.attr`.
**Prevention:** Never set a boolean HTML attribute (`hidden`, `disabled`, `checked`) through
the generic attribute writer. Use `U.show` or an explicit add/remove.

## [2026-07-31 — build] — One shared radius turned the settings panel into a circle

**Context:** Selecting the neon theme, whose gauges use `corner = 999` to mean "fully
round", then opening the settings menu.
**Error:** The whole menu panel rendered as a giant ellipse and was unusable. Reported by
the user from the preview at the same moment the audit caught it.
**Root cause:** One CSS custom property (`--radius`) fed both the gauge shapes and every
panel on the page. 999px is a legitimate gauge radius and an absurd panel radius.
**Fix:** Two properties: `--gauge-radius` carries the player's raw value, `--radius` is the
same value clamped to 24px. Gauge shapes read the former; everything rectangular reads the
latter.
**Prevention:** A player-controlled style value must never feed a UI surface the player is
not styling. Separate the custom properties at the point where the audiences separate.

## [2026-07-31 — build] — Theme default drifted from Config.Defaults

**Context:** Unit-testing the settings validator.
**Error:** `unknown speedometer rejected` expected the fallback to be the default cluster
and got a different one — the glass theme's patch named a speedometer that
`Config.Defaults.speedometer.style` did not match.
**Root cause:** The default theme and Config.Defaults are two statements of the same fact,
and nothing tied them together. A fresh install would have shown "Clear Glass" selected in
the menu while actually running a different cluster.
**Fix:** Aligned the two, and added a test that walks the default theme's entire patch and
asserts every leaf equals Config.Defaults.
**Prevention:** The drift test now runs in `test_settings.py`. When changing either side,
run it before reporting done.

## [2026-07-31 — build] — Truncate-then-compute destroyed config.lua

**Context:** A scripted batch edit over config.lua (the layout preset respacing).
**Error:** `config.lua` was 0 bytes; the next Write was rejected because the file changed
on disk since the last read.
**Root cause:** The patch helper opened the file for writing BEFORE computing the new
content: `open(path, 'w').write(fn(read()))` truncates at open, so the assertion failure
inside `fn` left a truncated file and nothing to write into it.
**Fix:** Rebuilt config.lua from the full known-good content. The patch scripts now compute
the complete result first and open for writing last.
**Prevention:** In any read-modify-write script: read, transform, assert, and only then
open for writing. The `w` mode truncates at open, not at write.

## [2026-07-31 — build] — Fixed-pixel heights over percentage positions collide at 720p

**Context:** The automated overlap sweep, re-run at 1280x720 after passing at 1920x1080.
**Error:** 61 overlap reports: the money row over the vehicle chips, the status column over
the speedometer, on layouts that were clean at 1080p.
**Root cause:** Element heights are fixed pixels but positions are viewport percentages, so
the pixel gap between two stacked elements shrinks with the window. A pair with 30px of
clearance at 1080p has 20px at 720p — and a column of gauges (270px) plus the tallest
cluster (244px) simply does not fit down one edge of a 720px screen at all.
**Fix:** Three parts. Bottom-anchored elements grow upward. A post-render clamp pushes
anything still overflowing back inside. And each layout preset now carries the gauge
direction it was designed around, because "everything down the left edge" is only possible
with gauges in a row.
**Prevention:** The sweep in the preview must be run at 1280x720 as well as 1080p before
declaring layouts safe. Small screen first: it is the constraining case.

## [2026-07-31 — install] — Junction in an ensured category folder silently not started

**Context:** First boot on the test server. v-hud was junctioned into
`resources/[standalone]/`, which server.cfg starts with `ensure [standalone]`.
**Error:** No error at all — every other resource in the category started, v-hud was never
mentioned anywhere in the log, and the HUD simply was not there.
**Root cause:** The category ensure started every real directory in `[standalone]` and
skipped the junction without a word. An explicit `ensure v-hud` starts the same junction
fine (v-phone has always run that way, with its own ensure line).
**Fix:** An explicit `ensure v-hud` in server.cfg after the framework.
**Prevention:** A junctioned resource always gets its own `ensure` line. Never rely on a
category folder to start a junction — and prefer the explicit ensure anyway, because
ensuring a missing name PRINTS an error while a category skips it silently.

## [2026-07-31 — install] — qb-core Commands.Add warning trace on boot

**Context:** First clean boot, `/hudadmin` registration.
**Error:** qb-core printed a yellow `> addCommand` / `> fn` trace pointing at
bridge/server/framework.lua on every start.
**Root cause:** `QBCore.Commands.Add(name, help, args, argsrequired, callback, permission)`
takes a permission STRING as its sixth argument. Bridge.addCommand passed the boolean
`true`, and qb-core warns when it tries to build an ace name out of a non-string.
**Fix:** `restricted and 'admin' or nil`.
**Prevention:** When wrapping a framework function, read its real signature in the qb-core
source rather than inferring it from the call site that inspired the wrapper.

## [2026-07-31 — in game] — backdrop-filter paints solid black rectangles

**Context:** First look at the Clear Glass theme in the running game.
**Error:** "Pleins de carré noir partout" — every glass panel, and the settings menu, drawn as
an opaque black box.
**Root cause:** FiveM's CEF composites the NUI layer OVER the finished game frame. The game
is not rendered behind the page, so `backdrop-filter` samples transparent black and paints
exactly that. The effect looks right in a browser, where there is a page behind it, and is
black in game — so it survives every test that is not run in the game.
**Fix:** No `backdrop-filter` anywhere. Glass is a translucent gradient, a lit top edge and a
drop shadow, all of which composite correctly. The player's blur slider now drives the edge
strength through `--frost`.
**Prevention:** `backdrop-filter` is banned in this resource. Any effect that reads what is
BEHIND the page cannot work in NUI; if a change needs one, it needs a different design.

## [2026-07-31 — in game] — CSS color-mix() is dropped, taking the whole declaration with it

**Context:** The settings panel in game: readable text and controls over a fully transparent
background, with the street visible straight through it.
**Error:** No console error. The panel simply had no background.
**Root cause:** `color-mix()` shipped in Chromium 111; FiveM's CEF is older. A declaration
containing an unsupported function is invalid and discarded ENTIRELY — so
`background: linear-gradient(160deg, color-mix(...), ...)` left the element with no
background at all. Twenty-nine uses across four stylesheets were silently doing nothing.
**Fix:** `U.mix()` in html/js/util.js, and state.js publishes every blend the stylesheets
need as a plain custom property (`--c-accent-a18`, `--c-bg-d88`, `--c-panel-tint`, ...).
**Prevention:** Only CSS that a 2022-era Chromium understands. No `color-mix`, no `oklch`,
no `:has()`, no container queries. Blends are computed in JS from the hex values, which are
right there in the settings anyway.

## [2026-07-31 — in game] — NUI focus stranded the player after the layout editor

**Context:** Move the HUD from the settings menu, drag an element, click Done.
**Error:** Cursor stuck on screen, no menu, no keybind working. Only a client restart fixed
it. Reported as "je reste bloqué après, je peux plus rien faire".
**Root cause:** The "Move the HUD" button closes the menu on the PAGE side with
`Menu.close(true)`, which deliberately does not post `close`. So Lua still believed
`State.menuOpen` was true, and the layout callback's `SetNuiFocus(layoutMode or menuOpen)`
evaluated `false or true` when Done was clicked. Focus was never released.
**Fix:** The `layoutMode` callback clears `menuOpen` when the editor opens.
`State.closeMenu()` no longer early-returns on "nothing is open" — it is the function that
gives the mouse back, so it must work when the flags are already wrong. Plus a watchdog that
releases focus if `IsNuiFocused()` is true while neither surface is open, and a
`/hudunstuck` command.
**Prevention:** NUI focus is the one state that can strand a player. Every path that sets it
must have a path that clears it, and there must be a way out that does not depend on the
page. Never early-return from a function whose job is to release focus.

## [2026-07-31 — in game] — os.time() does not exist on the client

**Context:** Saving settings after any change.
**Error:** `@v-hud/client/settings.lua:71: attempt to index a nil value (global 'os')`.
**Root cause:** The `os` library is server-only in the FiveM Lua runtime. The KVP writer used
`os.time()` for the timestamp that decides which stored copy of the settings is newer, so
every single save threw.
**Fix:** `GetCloudTimeAsInt()`, which is the client's UNIX clock and is directly comparable
with the server's `os.time()`.
**Prevention:** `os`, `io` and `package` are server-only. Before using a standard library in
a client file, check it exists there — the error surfaces at the first call, which may be a
long way from the change that introduced it.

## [2026-07-31 — in game] — The minimap moved opposite to the drag

**Context:** Dragging the minimap in the layout editor.
**Error:** The border followed the mouse; the map itself went the other way.
**Root cause:** Three coordinate systems, one of them inverted. The setting means "positive y
moves the map up"; the CSS frame uses `bottom`, where larger is higher; but the native
`SetMinimapComponentPosition` posY grows DOWNWARD even under 'B' alignment — which is why
the shipped geometry uses `y = -0.047` to lift the square map off the bottom edge. The Lua
was adding the offset with the wrong sign.
**Fix:** `dy = -(map.y) / 100`, with the three conventions written out in the comment.
**Prevention:** When a value crosses between CSS and a native, state both conventions in the
comment at the crossing point. A bare sign flip reads like a typo and gets "fixed" back.

## [2026-07-31 — in game] — `restart <resource>` serves the OLD stylesheet

**Context:** Fixing the transparent, left-aligned settings panel, then `restart v-hud`.
**Error:** The panel was still transparent and still left-aligned. The files on disk were
correct and every check passed. Reported as "réglage hud encore transparent et pas centré,
pourtant j'ai restart v-hud".
**Root cause:** FiveM's CEF caches NUI assets by URL and does not drop them when the resource
restarts. `restart` reloads the Lua and re-creates the page, and the page then re-uses the
CACHED `menu.css`. The only thing that cleared it was a full client restart — so a CSS fix
and a CSS fix that was never applied look identical, which is a miserable thing to debug.
**Fix:** `html/index.html` writes its `<link>` and `<script>` tags from a loader that appends
`?v=<timestamp>` per page load, so every resource restart fetches the current files.
`document.write` is used on purpose: it runs during parsing, so script order is preserved.
**Prevention:** Never diagnose a NUI change from a resource restart alone until this is in
place. If a page's assets are ever listed as plain tags again, this comes straight back —
`tools/make-preview.py` cross-checks its own asset list against the page for the same reason.

## [2026-07-31 — in game] — A focus watchdog built on IsNuiFocused() robbed every other NUI

**Context:** Connecting to the server; the qb-multicharacter screen.
**Error:** "Disposition enregistrée" toasted four times a second over the character list, and
pressing `I` there left the character stuck.
**Root cause:** Two of mine, compounding.

The watchdog added an hour earlier released focus whenever `IsNuiFocused()` was true while
this resource's own menu was closed. `IsNuiFocused()` is GLOBAL — it is true whenever ANY
resource holds focus. So on the multicharacter screen, which legitimately holds it, the
watchdog fired twice a second: it stole the cursor from qb-multicharacter and posted
`closeMenu`, which posted `layoutMode {on:false}`, which raised a toast. Every time.

And `openMenu` had no guard against another resource owning the screen, so `I` on the
character list took focus on top of qb-multicharacter's, leaving two pages fighting for the
cursor and neither able to give it back.

**Fix:** `State.focusHeld` — this resource tracks the focus it took, and the watchdog acts on
that alone. `openMenu` refuses while `IsNuiFocused()` is true or the HUD has not booted.
`closeMenu` only calls `SetNuiFocus(false)` if the focus was ours. `layoutMode` and
`Layout.setOpen` are idempotent, so the toast fires on a real transition and not on every
path that reaches them. Plus a release on `OnPlayerUnload` and on `onResourceStop`.
**Prevention:** `IsNuiFocused()` answers a question about the WHOLE client, never about this
resource. Read it to decide whether to take focus; never to decide whether to release it.
Track what you took, release only that.

## [2026-07-31 — in game] — The watchdog closed the menu the instant it opened

**Context:** Pressing `I` after the focus fix above.
**Error:** The menu appeared and shut itself immediately.
**Root cause:** A stale read across a `Wait`. The watchdog's loop chose its branch while
nothing was open, then slept 500ms, then acted on `State.focusHeld` — which by then was true
because the player had opened the menu DURING the sleep. The branch condition was half a
second old and the flag it acted on was current, so the two disagreed and the watchdog
"rescued" a menu that was working perfectly.
**Fix:** Re-read every part of the condition AFTER the wait, and require two consecutive
confirmations before acting. A genuine stuck cursor is still released within a second; a
transient can no longer trigger it.
**Prevention:** In any FiveM loop, a value read before a `Wait` is history. Anything the
branch depends on must be re-read after it — and a watchdog that takes a destructive action
should require the fault to persist rather than firing on a single sample.

---
