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

---
