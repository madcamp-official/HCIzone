# Desktop Pet — Handoff

Last updated: 2026-07-19 (pm: home is now a Pokéball with capture/release
light animations; earlier today: 25% size trim + real flap-flight fix)

## What this is

A transparent, always-on-top Godot 4 desktop pet. It stands on top of your
other windows, desktop icons, and the Dock; you can drag it, feed it, play
with it, and send it into a little house — which is meant as the handoff
point to a physical pet robot. Repo: `madcamp-official/HCIzone`, this project
lives at the repo root. Working branch: **`dev`**.

## Right now

- Local checkout is on `dev`, pushed up to commit `07d8005` (sprite
  characters + `.gdignore`).
- **Uncommitted changes on top of that**, not yet pushed: `pet.gd`,
  `project.godot`, `README.md`. These are:
  - Characters resized: first 4× (`SPRITE_SCALE` 2.5 → 10, ~300px tall) with
    the window grown to 760×720 to fit them, then trimmed 25% per user
    request (`SPRITE_SCALE` 10 → 7.5, ~220px tall).
  - A per-frame mouse-passthrough polygon around each sprite's actual opaque
    pixels, so the much-bigger transparent window stops swallowing clicks
    meant for whatever's underneath.
  - Fletchling's flight animation fixed (second attempt): `FlapAround` spins
    the bird through all 8 directions in one loop (the original "spinning
    while flying" bug); the first fix swapped flight to the `Walk` sheet, but
    that just looks like walking in midair. Now `FORM_DEFS` anim entries
    support a `"Sheet:first-last[:ticks]"` frame-subset syntax, and flight +
    carry use `FlapAround:0-1:5` — frames 0–1 of the facing row are a clean
    two-frame directional flap (verified by cropping the sheet: each row's
    18 frames start facing that row's own direction, then rotate), slowed to
    5 ticks/frame since the sheet's native 2 ticks is too twitchy for a loop.
  - **Upper-screen "walking on air" fixed**: the pet moves by moving its OS
    window, but macOS refuses to place a window above the menu bar, so feet
    could never rise above `window-top + FOOT_Y` (~60% down the screen) even
    though the physics said they had — it walked on air below high ledges.
    Now all `win.position` writes go through `_place_window()`, which clamps
    the window to the usable-rect top and turns the refused remainder into
    `vis_off`, an in-window offset applied to the Node2D `position`, the
    mouse-passthrough polygon, and the drag grab-offset. Don't read
    `win.position` back to detect the clamp — the getter returns stale
    values depending on frame timing (that bug was hit and fixed here).
    The ledge filter headroom also went from a flat 40px to ~0.75× the
    character's height so it won't perch with its head inside the menu bar.
  - Physics constants (jump height, fly/walk/home speed, the house roof
    perch width) scaled up to match the bigger character.
- **The home is now a Pokéball** (uncommitted, on top of the above):
  `home.gd` was rewritten to render the classic red ball from the leftmost
  64×64-cell column of `pokeball sprite.png` (loaded from disk at runtime,
  same as the character sheets). Sending the pet home now plays a capture:
  the ball opens (col-0 frames 4-6), flares with the sheet's burst/ring
  frames (7-14) while the pet shrinks into the ball's center washed out to
  white-hot light, then snaps shut. Letting it out plays the release frames
  (20-24) with the pet beaming back out. While occupied the ball's button
  blinks red, it wobbles occasionally, and leaks sparkles. (Procedural glow
  discs were tried first and removed — big low-alpha circles read as a gray
  background on the desktop; the burst frames are instead tinted past white
  during transfers so their baked-in gray smoke reads as light.)
  pet.gd drives the ball's frames
  each transfer tick via `home_node.set_transfer(mode, progress)`, so the two
  windows can't drift. Home window is now 320×260 (`HOME_FLOOR` 200,
  `HOME_DOOR_X` 160 = ball center), `ENTER_TIME` 1.6 s, and the ball window
  only catches clicks in a box around the ball (passthrough polygon).
  The old "house not resized for the 4× characters" gap is thereby resolved —
  a Pokéball is *supposed* to dwarf what goes into it.
- **Ball-crown perch no longer traps the pet.** The crown is only ~2 px of
  standable width, so a cat couldn't pace off it and a gentle near-vertical
  hop just dropped straight back onto it — pets got marooned up there.
  `_try_hop` now (a) rejects any arc that would re-cross its own launch
  ledge mid-descent (general fix: `x_cross` at `t = 2*t_up` must clear the
  perch), (b) samples a wider spread + retries 5× per ledge off a "cramped"
  perch so a clearing arc is actually found, and the IDLE handler hops off a
  cramped perch eagerly (`_on_cramped_perch()`, ~1 s) instead of loitering or
  napping on it. Verified: spawned onto the crown, leaves within ~1 s across
  repeated runs. Birds were never affected (they fly off via `_fly_to`).
- The pre-existing Godot game instance from ~10:53am was accidentally killed
  by an over-broad `pkill` during today's testing (mea culpa); a fresh
  instance running the new Pokéball code was launched in its place with
  `PET_NO_ICONS=1` (see below). Relaunch from the editor if you want the
  desktop-icon ledges back.
- **Shadows are now the sheets' own pixel shadows**: `_load_form_sprites`
  also loads each anim's `<Anim>-Shadow.png` (PMD marks the shadow ellipse
  per frame in blue/red/green/white size layers, centered on the ground
  line), recolors every marked pixel to black, and `_draw_pet_shadow` draws
  that frame region translucent (alpha 0.20) under the sprite with the same
  transform/ledge-clipping as before; smooth-ellipse `_draw_shadow` remains
  as the fallback for sheets without a shadow file. Don't re-add a
  bottom-anchoring shift: PMD centers the ellipse on the feet line, and
  anchoring its bottom there pushes it up behind the body (tried, reverted).
  On ledges narrower than the shadow itself (the ball's 82 px crown) the
  whole shadow scales down to fit instead of getting its sides chopped off
  (`shalf` in the sheet dict = shadow content half-width, measured at load).
  The ball's shadow in home.gd is a matching chunky 3-row pixel ellipse.
  **The shadow is clipped at the feet line** — `_draw_pet_shadow` draws only
  the frame rows down to `sp.foot` (dest y ≤ 0), so just the upper half of
  the ellipse shows. Its lower half would hang below the ledge/Dock top and
  either get occluded (reads as a shadow "behind" the window) or, if raised
  to compensate, float detached and kill the flat 2D look. Clipping keeps it
  tucked flat under the feet. (An earlier `slift`/lift attempt was reverted
  for exactly that detached look — don't reintroduce a vertical shift.) The
  ball's home.gd shadow rows were likewise nudged fully above its floor line.
  **The side-edge clip is snapped to the pixel grid.** A pet at a window's
  edge does get its shadow clipped (letting it float past the edge looked
  worse), but `_draw_pet_shadow` snaps the clip to whole shadow pixels
  (`col_l`/`col_r`, each source pixel = SPRITE_SCALE wide) so the cut lands
  on a chunky pixel boundary instead of a razor-thin sub-pixel slice — it
  reads as part of the pixel art. On a wide ledge (Dock) `col_l=0,
  col_r=fw` → full shadow, unchanged. (To test the clip deterministically:
  the CoreGraphics helper only reports layer-0 windows, so an always-on-top
  test window isn't seen as a ledge, and the cluttered desktop fragments a
  normal test window's ledge; a temporary `PET_TEST_SHADOW_HALF` hook that
  forced a clip near the feet was used to verify the chunky edge, then
  removed.)
- **Play/nap effects are now PMD move_VFX sprites** (`_load_vfx` /
  `_draw_vfx` in pet.gd): play mode spawns the musical-notes animation
  (`sprites/move_VFX/0007/001`, 18 loose PNG frames, 88×48 canvas) on
  toggle and on each cursor "catch"; napping spawns the wobbling Zzz
  (`sprites/move_VFX/0078/<n>/000.png`, 8 frames with *varying* canvas
  sizes — that's why VFX draw bottom-center anchored). VFX particles are
  stationary one-shots at `VFX_SCALE` (= SPRITE_SCALE/3 — full world scale
  looked comically huge, user asked for 1/3; notes then re-bumped to
  1.5×VFX_SCALE per user, per-kind `sc` in `_vfx`; the frames animate
  internally). Notes frame `011.png` is deliberately skipped at load: it's
  a baked-in one-frame blink (right note vanishes, returns on 012) that
  reads as flicker at our 0.07 s/frame — and `017.png` never existed in the
  rip (the blank half of the ending blink), so don't "fix" the numbering.
  The heart burst (boop / fed, `0051/000`) and the hungry mark (`0121/004`)
  are also move_VFX now — every floating particle goes through `_draw_vfx`;
  the old procedural `_draw_heart` and cookie-thought-bubble were removed.
  Single-folder VFX (notes/heart/hungry) load via `_load_vfx_folder`; missing
  frame indices in a folder are just skipped (hungry has no `006.png`).
  `PET_NAP=1` env forces a quick nap for testing, and `PET_SNAP_AT`'s
  floor is now 0.5 s to catch these short animations. The heart/hungry
  spawns sit `+95 px` below `_above_head` so they read as coming off the pet.
- **The snack is an apple / golden apple** cropped from `sprites/items.png`
  (Food row: apple at 100,61 and golden apple at 116,61, each 13×15;
  `_load_snack` keys out the sheet's opaque teal bg). `_feed` rolls
  `eat_gold` (golden 25%). It's held at each character's mouth via a per-form
  `mouth = Vector2(fwd, up)` in `FORM_DEFS` (that anim's own sprite px:
  forward of center, up from the feet line) — Eevee (6,11), Snorlax (7,24),
  Fletchling (9,11). The eat anims (Snorlax Swing, Fletchling Attack) rotate
  the mouth per frame, so a static anchor is a best-fit, not pixel-perfect.
  The old procedural cookie was removed.
- The resize/flight fix + Pokéball home + pixel shadows + VFX were committed
  and pushed to `dev` as `e748721`.
- The ball-crown-trap fix, the shadow-clip fixes, the heart/hungry +
  apple-snack sprite swaps, and the per-character food mouth anchors (all in
  `pet.gd`, plus the ball-shadow row nudge in `home.gd` and the new
  `sprites/items.png`) are committed and pushed to `dev` on top of `e748721`.
  Nothing is left uncommitted.
- **`fix/virtual_bot_minor_error_fixing` is merged into `dev`.** It brought
  pet.gd fixes: a dropped parrot now settles where it was released
  (`_drop_release`, `DROP_SNAP_UP`) instead of flying off to a random perch;
  `_fly_step` retargets a moving app window mid-flight; the fall safety net
  uses the usable rect so it can't land under the Dock; `_rebuild_platforms()`
  runs once in `_ready()` so the first flight target isn't picked against an
  empty list; `H`/`enter_home` again cancels a trip already underway (as does
  play mode); `_go_home_tick` steps off the ball crown when it's above the
  door; `_feed` ignores mid-hop; and a form whose sheet failed to load gets
  the all-passthrough polygon instead of swallowing every click.
  Only conflict was `_ready()` — `_load_snack()` vs the moved
  `_begin_flight()`; both were kept.
- **`feature/arduino_code` is merged into `dev`** (fast-forward). The robot
  firmware now lives under `firmware/`: `main_robot/main_robot.ino` is the
  real robot (non-blocking millis() state machine: IDLE→DRIVE→AVOID/CLIFF→
  HOME→ARRIVED, HC-06 Bluetooth `F/S/H/G/?` commands, HC-SR04 obstacle
  avoidance, KY-032 cliff guard checked every loop, dual KY-022 IR-beacon
  homing), `tests/01..08` are per-sensor bring-up sketches, and
  `firmware/00_통합_핀맵.md` is the pin map. `bridge.py` at the repo root is
  the host-side bridge. The earlier `desk_pet_robot/desk_pet_robot.ino`
  skeleton was removed in favor of `main_robot`. A stray committed
  `__pycache__/*.pyc` was untracked and `__pycache__/` + `*.pyc` added to
  `.gitignore`.

## What's implemented

- **Platforming physics** (`pet.gd`): gravity, ballistic jumps (cat-style
  characters) vs. gravity-free directional flight (bird-style), landing on
  window top edges, desktop icons, and the Dock. Window edges come from
  `helpers/window_list.c` (macOS, CoreGraphics) or `helpers/window_list_win.c`
  (Windows, contributed by a teammate on `dev`); desktop icons come from
  `helpers/desktop_icons.applescript` (macOS/Finder only).
- **Three characters**, `B` cycles between them (`Form` enum in `pet.gd`):
  - **Eevee**, **Snorlax** — walk + ballistic jump ("cat" behavior)
  - **Fletchling** — walk + directional flight ("bird" behavior)
  - Rendered from PMD-style sprite sheets in `sprites/<Name>/` (`AnimData.xml`
    + `<Anim>-Anim.png`), loaded straight from disk at runtime via
    `Image.load_from_file` — bypasses Godot's import system entirely, which
    is why `sprites/.gdignore` exists (stops the editor from trying to
    auto-import ~180 loose PNGs as engine textures on project open).
  - State → animation sheet mapping is `FORM_DEFS` at the top of `pet.gd`.
- **Interactions**: drag to carry, right-click to feed (cookie), left-click
  (no drag) to boop, middle-click/`P` for play mode (chases the cursor), naps
  on its own, wanders, hops/flies between ledges autonomously.
- **The home** (`home.gd`): a Pokéball in its own always-on-top window,
  sitting on the Dock line. Click it or press `H` to recall the pet — it
  walks/flies over, the ball opens and flashes, the pet beams in as light and
  "vanishes" (window hidden + fully click-through, since Godot can't hide its
  main window). Clicking again releases it in a burst of rays. Ball art =
  leftmost column of `pokeball sprite.png`, frame indices documented at the
  top of `home.gd`.
- **Virtual↔real bridge**: `~/.desktop-pet/` (`state`, `command`,
  `on_enter_home`/`on_exit_home` hooks) — the intended handoff to a physical
  robot. A working example is wired up: `helpers/arduino_led.sh` +
  `helpers/arduino/led_bridge/led_bridge.ino` light an LED over serial when
  the pet enters/exits home. Currently the two hooks in `~/.desktop-pet/`
  call that script; swap them for real robot wake/sleep commands when ready.

## How to run / verify

- Godot binary on this machine: `/Users/young/Downloads/Godot.app/Contents/MacOS/Godot`
  (not on PATH, not in /Applications).
- Quick parse check: `Godot --headless --path desktop-pet --quit`
- Real run with diagnostics: `PET_DEBUG=1 Godot --path desktop-pet` — logs
  state/form/animation/detected ledges once a second.
- Useful env vars: `PET_SPAWN="x,y"`, `PET_FORM=eevee|snorlax|fletchling`,
  `PET_PLAY=1`, `PET_SNAP=/path.png` (saves one viewport screenshot — plus
  the ball window as `…-home.png` — at `PET_SNAP_AT` seconds, default ~2s;
  the reliable way to visually check rendering without screen-recording
  permissions, which `screencapture` doesn't have in this shell).
- **`PET_NO_ICONS=1` matters when launching from a shell like this one**: the
  Finder-icons osascript hangs forever on the unanswerable automation-
  permission prompt, and because icons, windows, and bridge commands share
  one poll thread, that hang freezes ledge updates and `command`-file
  handling for the whole session (this is also a latent robustness bug worth
  fixing — see next steps). To exercise the capture/release animation
  headlessly: launch with `PET_BRIDGE_DIR` pointing at a scratch dir,
  `PET_SPAWN` near the ball, then `echo enter_home > $BRIDGE/command`
  (and later `exit_home`) and snap with `PET_SNAP`/`PET_SNAP_AT`.
- **Always check for and avoid conflicting with already-running Godot
  instances first** (`ps aux | grep -i "Godot.app/Contents/MacOS/Godot"`) —
  they can be the user's own live session, and multiple instances polling
  `~/.desktop-pet/command` at once will race each other.

## Known gaps / next steps

- **The poll thread has no timeout on its `OS.execute` calls** — an osascript
  stuck on an unanswered Finder-automation prompt blocks windows, icons, AND
  bridge-command polling forever (observed live today; that's why the current
  session runs with `PET_NO_ICONS=1`). Worth moving the icon poll to its own
  thread or adding a watchdog.
- The flash frames extend past the ball window's bottom edge by design
  (`HOME_H` trades 60 px of below-Dock overhang for flash size); if the big
  ring looks clipped on a small Dock, grow `HOME_H` / shrink
  `home.gd`'s `BALL_SCALE`.
- `main.gd`, `parrot.gd`, `fly.gd` are leftover files from a teammate's merge
  of the old standalone `feature/parrot` demo into `dev`. They're not wired
  into `project.godot`'s `run/main_scene` (still `main.tscn` → `pet.gd`), so
  they're inert, but could be deleted for clarity.
- Everything described above is committed on `dev`; the working tree is
  clean (see "Right now").
