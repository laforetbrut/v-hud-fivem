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

## [2026-07-31 — in game] — The HUD was flung into the corners after a server restart

**Context:** Reconnecting after a server reboot.
**Error:** Elements pinned to the extreme corners of the screen, sometimes.
**Root cause:** The viewport clamp ran before the first settings message had been applied, so
it measured elements sitting at their CSS defaults — `left: 50%`, `top: 50%`, zero size — and
wrote corrections computed from positions nobody had chosen. Those corrections then survived
the real layout. It was intermittent because it depended on whether the boot payload arrived
before or after the first animation frame.
**Fix:** The clamp returns immediately unless `state.ready` and settings exist; a correction
larger than half the screen is refused as a symptom rather than applied; elements larger than
the viewport are left to overflow; and three settle passes run after boot instead of one.
**Prevention:** A layout correction is only meaningful once there is a layout. Anything that
measures the DOM must refuse to run before the first real render, and a correction big enough
to move something across the screen is a bug report, not a fix.

## [2026-07-31 — in game] — Layout editor grab boxes did not sit on their elements

**Context:** The layout editor, after docking was introduced.
**Error:** The dashed boxes were near the elements rather than on them.
**Root cause:** The ghosts were reconstructed from the stored `x`/`y` percentages. Those
describe the element only for a free element at scale 1 — a docked element ignores them
entirely and follows the minimap, a clamped element carries a `--fix` offset, and everything
is scaled by `--hud-scale`.
**Fix:** Every ghost is measured from the live element's bounding box, in pixels. A docked
one is drawn in a different colour, because dragging it releases it from the map.
**Prevention:** To draw something over an element, measure the element. Never rebuild its
position from the inputs that were supposed to produce it.

## [2026-07-31 — in game] — The minimap resized itself on every settings change

**Context:** Moving any slider in the settings menu.
**Error:** The minimap jumped to full size and snapped back. Reported as "on voit la minimap
changer de taille avant de redevenir normal".
**Root cause:** `Minimap.apply` ran the `SetBigmapActive(true) / Wait(50) / SetBigmapActive
(false)` rebuild every time it was called, and it is called on every settings change. That
toggle exists to make a new radar MASK take effect; it is a visible flicker and it is only
needed when the SHAPE changed. Moving, resizing or recolouring the map needs none of it -
`SetMinimapComponentPosition` takes effect immediately. Dragging a slider also started one
thread per frame, each with its own 50ms wait, so the flickers overlapped.
**Fix:** The rebuild only runs when the shape actually changed, and calls are coalesced
behind a token so only the last change in a burst is applied.
**Prevention:** Before putting an expensive or visible native call in a function that runs on
every settings change, ask which SETTING it is actually for, and guard it on that one.

## [2026-07-31 — in game] — The HUD drew over the phone and the pause menu

**Context:** Opening v-phone, and opening the GTA pause menu.
**Error:** The speedometer and the minimap sat on top of both.
**Root cause:** Only `IsPauseMenuActive()` was checked, and only for the HUD elements - not
the minimap - so anything that was not the pause menu was simply not considered.
**Fix:** `Compat.overlayOpen()`, driven by `Config.HideWhen`: the pause menu and loading
screen, NUI focus held by any other resource, and a list of resources asked through the "am I
open" export they already publish (`exports['v-phone']:IsOpen()`). Both the HUD and the
minimap read it. Nothing reaches into another resource - it asks a question that resource
already answers, and a missing export is recorded once and never asked again.
**Prevention:** "Is something else on screen" is not the same question as "is the pause menu
open". When integrating with another resource's visibility, use the signal it publishes;
never patch it, and never assume the export exists.

---

## [2026-07-31 19:40] — Speedometer preview cards blank in game

**Context:** The settings menu speedometer picker. Ten cards, each showing a scaled copy of
an instrument. Correct in a browser, empty frames in game, across two fix attempts.
**Error:** Cards rendered with their label and background but no visible instrument.
**Root cause:** `setArc()` sizes a stroked arc from `node.getTotalLength()` and caches the
result on the node. `getTotalLength()` returns 0 for a path that is not in the document, and
`preview()` painted the face while it was still detached, so the zero was cached and
`if (!node.__length) return` skipped that arc for the rest of the page's life. The first fix
attempt made the build synchronous, which made it worse: the previous `requestAnimationFrame`
had at least let the card attach first.
**Fix:** Never cache a zero length, and repaint the cards from `renderContent()` once they
are in the document.
**Prevention:** A cache keyed on "have I computed this yet" must distinguish "not yet" from
"computed as zero". More generally, any geometry read - `getTotalLength`, `getBoundingClientRect`,
`getComputedStyle` - answers meaninglessly for a detached node, so building off-document is
only safe for work that needs no measurement.

---

## [2026-07-31 19:55] — Driving warnings lost their first tick

**Context:** New belt and door chimes, under test on real Lua before shipping.
**Error:** The grace period was measured from the second tick, not the first, so the chime
was late by one tick interval and "once per occurrence" could mean "once, ever".
**Root cause:** `0` was used both as the "not started" sentinel and as a valid `GetGameTimer()`
value, so the first call stored 0 and the next call still read it as unset.
**Fix:** `nil` as the sentinel, cleared on both fields when the fault goes away.
**Prevention:** Never use a value the domain can actually produce as an "unset" marker. Zero
is a real timestamp.

---

## [2026-07-31 20:05] — HUD drawn over the quit confirmation

**Context:** Alt+F4 in game.
**Error:** The minimap, gauges and speedometer stayed on screen over "Voulez-vous vraiment
quitter Grand Theft Auto V ?".
**Root cause:** That prompt is a frontend WARNING MESSAGE, a different screen from the pause
menu, and the pause menu is already closed behind it - so `IsPauseMenuActive()` is false.
**Fix:** `IsWarningMessageActive()` and `IsPlayerSwitchInProgress()` added to
`Compat.overlayOpen()`, behind `Config.HideWhen.frontend`, looked up through `_G` so a build
missing either native skips the check instead of erroring on the tick.
**Prevention:** "The game put something full-screen up" is several different natives. The
pause menu is only one of them.

---

## [2026-07-31 21:30] — Speedometer preview cards blank in game (second, real cause)

**Context:** Third report of the same symptom. The first fix (never cache a zero
`getTotalLength`) was necessary but not sufficient.
**Error:** Cards showed their label and background, no instrument at all — not even the plain
large text of the speed number.
**Root cause:** The cards were `<button>` elements. Chromium's UA stylesheet, up to and
including 103 — which is the CEF FiveM ships — contains `align-items: flex-start` for
`button`. In a `flex-direction: column` card the cross axis is horizontal, so that one
declaration sizes every child to its own content instead of stretching it. `.spd-preview`
declares no width, and its only child was `position: absolute`, i.e. out of flow, so its
max-content width was **0**; `overflow: hidden` then clipped the whole face away. The label
survived only because text has an intrinsic width. Chrome removed that UA rule years ago,
which is exactly why the same page was correct in a desktop browser and empty in game.
**Fix:** The cards are `div`s with `role="button"`, `align-items: stretch` is stated
explicitly anyway, and the face stays in normal flow scaled by a `transform` — no absolute
positioning, no percentage offsets, no negative translate. The same bug was collapsing the
theme colour swatches to a 26px sliver.
**Prevention:** A browser is not a proxy for CEF. When a page is right in Chrome and wrong in
game, suspect a UA-stylesheet or feature difference from Chromium ~90-103 BEFORE suspecting
the page's own logic — and reproduce it by injecting the old UA rule into the harness, which
is what finally turned this from a guess into a measurement.

---

## [2026-07-31 21:40] — Moving the minimap showed terrain from where it used to be

**Context:** Dragging the minimap to a new place on screen.
**Error:** A large slab of ground with no mask edges and the player blip missing, framed by a
border sitting somewhere else.
**Root cause:** `SetMinimapComponentPosition` updates `minimap_mask` and `minimap_blur`
immediately, but the `minimap` component — the one carrying the terrain and the blips — only
re-reads its rectangle when the minimap is REBUILT. The rebuild was gated on `shapeChanged`,
a change made earlier to remove a resize flicker. So a move repositioned the hole, the blur
and the CSS border and left the map render behind. A regression from the flicker fix.
**Fix:** Gate the rebuild on a signature of the whole geometry (shape, dx, dy, scale, aspect),
and drop the rebuild wait from 50ms to a single frame so it is not a visible jump. The
watchdog that closes an unrequested bigmap now needs two consecutive strikes, because the
rebuild window is hit far more often than it used to be.
**Prevention:** "The native took effect" and "the engine re-read it" are different claims.
Before gating an expensive call on a narrower condition, check what else that call was
quietly doing.

---

## [2026-07-31 23:10] — Headlight tell-tales never changed

**Context:** Switching the headlights and the main beam on and off in a vehicle.
**Error:** The lights lamp never lit and the main-beam lamp never appeared.
**Root cause:** Two independent bugs on one line, either of which was enough on its own.

`GET_VEHICLE_LIGHTS_STATE` is `BOOL fn(Vehicle, BOOL* lightsOn, BOOL* highbeamsOn)`, so Lua
receives THREE values and `pcall` puts its success flag in front of all of them, making four.
The code destructured three: `local ok, lightsOn, highBeams = pcall(...)`. So `lightsOn` held
the native's return value, `highBeams` held the real `lightsOn`, and the real high-beam value
was discarded.

On top of that, both were compared with `== 1`. Cfx hands BOOL out-parameters back as `true`
on some builds and as `1` on others, and `true == 1` is false in Lua — so on a boolean build
neither lamp could ever light regardless of the shift.
**Fix:** Destructure four (`ok, _, lightsOn, highBeams`) and test with a helper that accepts
`true` or a non-zero number. Main beam now also implies the headlights are on, because a lit
main-beam lamp beside a dark headlight lamp reads as a broken HUD.
**Prevention:** Count the return values of any native with out-parameters, and remember pcall
adds one. Never compare a Cfx BOOL out-parameter with `== 1` or with `== true`; test both.
A regression test that stubs the native in BOTH shapes is what makes this stay fixed.

---

## [2026-07-31 23:20] — Engine lamp stayed green with the engine switched off

**Context:** Turning the engine off while sitting in the car.
**Error:** The engine tell-tale stayed lit green.
**Root cause:** The lamp was driven by `data.engine`, which is engine HEALTH as a percentage,
not whether the engine is running. A switched-off car in perfect condition scored 100 and lit
green.
**Prevention:** "Healthy" and "running" are different questions. When a symbol answers a state,
check that the value behind it actually measures that state and not a neighbouring one.
**Fix:** Read `GetIsVehicleEngineRunning` as well; the lamp is green only when running AND
healthy, red when damaged either way, and dark when the engine is off.

---

## [2026-07-31 23:55] — Seatbelt lamp updated on fastening but not on unfastening

**Context:** Buckling and unbuckling the seatbelt in a vehicle.
**Error:** The lamp went green when the belt was fastened and stayed green after taking it off
- a HUD that reports the opposite of the truth, which is worse than one that reports nothing.
**Root cause:** The belt state was MIRRORED rather than read. Two mechanisms fed a local copy
and both have one-way holes:

  * The event latch is only as good as the other script's discipline about firing in both
    directions. qb-smallresources' own harness path is the counter-example - `toggleHarness()`
    calls `toggleSeatbelt()` when a harness goes ON and returns early when it comes OFF, so
    nothing is fired and any mirror is stuck showing a belt that was removed.
  * The state bag was re-read every tick and won unconditionally, so a script that writes it
    true on buckling and never writes it false pinned the lamp on forever, one frame after the
    unbuckle event had correctly cleared it.

**Fix:** Ask, do not mirror. `qb-smallresources` publishes `HasSeatbeltOn` and `HasHarness`;
those are tried first and cannot drift. The event latch and the state bag remain as fallbacks
for scripts that publish neither, and the bag is now only consulted when no event has ever
arrived. `/hudinfo` prints which source answered, so a wrong indicator says why.
**Prevention:** When another resource owns a piece of state, read it from that resource if it
offers a way. A local copy kept in sync by events inherits every gap in the other script's
event discipline, and those gaps are invisible until someone reports the symptom.

---

## [2026-08-01 01:15] — My own Lua compile check passed every broken file

**Context:** Verifying edits to locales/fr.lua.
**Error:** A genuine syntax error (an unescaped apostrophe inside a single-quoted string)
shipped through a check that reported "all lua compiles".
**Root cause:** The check was `load(src, name) is None`. Lua's `load` returns `nil, message`
on failure, and lupa hands that pair back as a TUPLE - which is never `None`, so every file
passed regardless of whether it compiled. The check had been reporting success for the whole
session without testing anything.
**Fix:** The boolean now comes from Lua itself: `local f, err = load(...) if f then return
true, "" end return false, err`. FiveM's backtick hash literals are stripped first, since they
are a Cfx extension standard Lua rejects and would otherwise be reported as failures.
**Prevention:** A test harness that cannot fail is worse than no harness - it converts "not
checked" into "checked and fine". Prove a new check catches a deliberately broken input before
trusting it. Two real bugs this session were only found because the check was made to fail
first on the old code; this one was found by accident.

---
