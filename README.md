# Desktop Pet

A tiny desktop pet that lives in a transparent, always-on-top window on your
screen. Three characters, rendered from PMD-style sprite sheets in
[sprites/](sprites/): **Eevee** and **Snorlax** behave like the cat (walk +
ballistic jumps), **Fletchling** behaves like the bird (flies between ledges).

## Run it

Requires **Godot 4.2+** (no install here yet: `brew install --cask godot`).

- Open the Godot project manager, **Import** this folder, and press **F5**, or
- from a terminal: `godot --path /path/to/desktop-pet`

## Controls

| Input | What happens |
|---|---|
| Left-drag | Carry the cat anywhere on screen (its feet dangle) |
| Left-click (no drag) | Boop — a heart burst pops up; wakes it from a nap |
| Right-click | Feed it an apple (rarely a golden apple) |
| Middle-click or `P` | Toggle play mode: it chases your cursor |
| `B` | Cycle character: Eevee → Snorlax → Fletchling |
| Click the Pokéball | Recall the pet into the ball / let it back out |
| `H` | Same as clicking the ball |
| Drag the Pokéball | Slide it along the Dock line |
| `Esc` / `Q` | Quit |

## Behavior

- **Walks on your windows, desktop icons, and the Dock.** The pet has gravity:
  it falls until it lands on the top edge of another app's window, a visible
  desktop icon, or the Dock line, and paces along whatever it landed on. It
  rides windows that move, falls (with a squish) when its perch is closed or
  slid out from under it, and sometimes deliberately walks off an edge. Drag it
  and drop it onto a window or icon to perch it there. Its shadow — the
  translucent pixel ellipse from the sprite sheets' own `<Anim>-Shadow.png`
  markers — rests on the ledge it's standing on, clipped to the ledge's
  edges, and absent mid-air.
- **Play mode** (middle-click or `P`): it sprints after your cursor along its
  ledge, pounces into the air when the cursor is overhead, chases right off
  edges — bursts of pixel musical notes (the PMD VFX from
  `sprites/move_VFX/0007/001`) pop when it catches the cursor — and after
  ~35 s it's all tired out and will nap soon.
- **Hops around on its own.** Every so often it spots another ledge in jumping
  range — a window edge, a desktop icon, sometimes the Dock — crouches, and makes
  a proper ballistic leap onto it (it has cartoon legs: up to ~950 px straight
  up). Icons make natural stepping stones from the Dock up to window tops.
- **Wanders** left and right along its current ledge now and then.
- **Naps** after 25–60 s awake: eyes close, it squashes down, and a wobbling
  pixel "Zzz" (the PMD sleep VFX from `sprites/move_VFX/0078`) hovers over
  it. Naps last
  12–25 s unless you wake it.
- **Gets hungry** after ~45 s without food: a spiky pixel mark (the PMD VFX
  from `sprites/move_VFX/0121/004`) flashes over its head. Feeding resets
  hunger — and pops a heart burst (`sprites/move_VFX/0051/000`), the same one
  a boop or being fed shows.
- **Characters** (`B` cycles): Eevee and Snorlax use the cat behavior; sleep,
  play, feeding, wandering, and going home are identical — the only difference
  is how gaps between ledges are crossed: a crouch and a ballistic jump under
  gravity. Fletchling uses the bird behavior: a smooth, gravity-free flight
  straight to the target perch, so falling off a vanished ledge or being
  dropped mid-air becomes a flight to the nearest perch instead of a plummet.
  Switching mid-air works — a mid-flight shapeshift.

## Sprites

Characters are drawn from PMD-style sheets in [sprites/](sprites/)
(`<Name>/<Anim>-Anim.png` + `AnimData.xml` with frame sizes and 60 Hz-tick
durations). Sheets load straight from disk at runtime via `Image.load_from_file`
on an absolute path — bypassing Godot's resource/import system entirely, so no
editor import pass is needed. A `sprites/.gdignore` marker tells the editor to
skip that folder outright (otherwise it tries to auto-import all ~180 PNGs as
engine textures on project open, which is slow and can leave the project stuck
"still importing" if you hit Play too soon — if you ever see that, `.gdignore`
is the fix). Rows are the 8 PMD directions (row 2 = right, row 6 = left; the pet
only uses those two), columns are frames; single-row sheets (e.g. Sleep) get
mirrored for the left side. Each sheet's feet line is auto-calibrated by
scanning frame 0's alpha, so every animation stands on the same ground line.
State → sheet mapping lives in `FORM_DEFS` at the top of [pet.gd](pet.gd):
Idle, Walk, Sleep, Hop (jump crouch), Hurt (mid-air), Eat/Swing/Attack
(eating), Float (carried). An entry may also name a frame subset,
`"Sheet:first-last[:ticks]"`. Fletchling's **flight** (and being carried) is
`FlapAround:0-1:5`: the FlapAround sheet spins the bird through all 8
directions within one loop (playing it whole looks like tumbling), but frames
0–1 of the facing row are a clean two-frame directional flap, slowed to 5
ticks per frame.

Characters render at `SPRITE_SCALE` (7.5× the source pixels, ≈220 px tall). The
window is 760×720 to fit them, so only the box around the sprite itself accepts
mouse clicks — everything else passes through to whatever is underneath (updated
every frame from the current frame's opaque bounds). The pet moves by moving its
OS window; macOS won't place a window above the menu bar, so near the top of the
screen `_place_window()` clamps the window and draws the sprite (and its click
box) shifted up inside it by the difference (`vis_off`) instead.

## The home, and the virtual ↔ real bridge

A classic red Pokéball (its own transparent window, rendered in
[home.gd](home.gd) from the leftmost column of `pokeball sprite.png`) sits on
the Dock line; drag it sideways to place it. Click it (or press `H`) and the pet
travels there — walking its ledge, marching off edges, falling, resuming — then
the ball opens, flares with light, and the pet shrinks into it as a white-hot
streak before the ball snaps shut. While it's inside, the ball's button blinks
like a red LED, it wobbles now and then, and it leaks little sparkles. Click
again and the ball bursts
open in a flash of rays as the pet beams back out. It also goes home by itself
every few minutes, and the ball's crown is a (precarious) hoppable perch.

Going home is the **handoff point to a physical pet robot**: the idea is that the
soul leaves the screen and wakes up in the robot. Everything an external
robot-bridge process needs lives in `~/.desktop-pet/` (override with the
`PET_BRIDGE_DIR` env var):

| File | Direction | Meaning |
|---|---|---|
| `state` | pet → robot | Current holder of the soul: `virtual` or `home` (= robot's turn) |
| `command` | robot → pet | Write one of `enter_home`, `exit_home`, `feed`, `play`; the pet reads and deletes it within ~0.3 s |
| `on_enter_home` | pet → robot | Executable hook, run (non-blocking) the moment the cat finishes entering — wake the robot here |
| `on_exit_home` | pet → robot | Executable hook, run when the cat is let back out — put the robot to sleep here |

So the robot loop is: watch for `on_enter_home` (or poll `state`), animate the
physical pet, and when the robot should hand back, write `exit_home` into
`command`.

### Worked example: an LED on an Arduino

[helpers/arduino/led_bridge/led_bridge.ino](helpers/arduino/led_bridge/led_bridge.ino)
is a tiny sketch that listens on serial (9600 baud) for `ON\n` / `OFF\n` and
drives an LED — the onboard LED by default, no wiring needed, or wire an
external LED (through a ~220ohm resistor) to pin 13 for something more visible.
Upload it once with the Arduino IDE (select your board and port, hit Upload).

[helpers/arduino_led.sh](helpers/arduino_led.sh) is the shell side: `arduino_led.sh
on` / `off` auto-detects the board's serial port and sends the command (macOS
only — uses `stty -f`). Override the port with `ARDUINO_PORT=/dev/cu.xxxx` if
auto-detection picks the wrong device; override baud with `ARDUINO_BAUD`. If no
board is plugged in it just prints a note and exits 0 — safe to leave wired into
the hooks all the time.

`~/.desktop-pet/on_enter_home` and `on_exit_home` already call
`arduino_led.sh on` / `off` as their example action (alongside a debug line
appended to `~/.desktop-pet/hook.log`), so plugging in a board with the sketch
uploaded and sending the cat home should light its LED immediately — no further
setup. Swap those two lines out for your actual robot's wake/sleep commands
when you're ready.

## How window detection works

Godot can't see other apps' windows, so [helpers/window_list.c](helpers/window_list.c)
is a tiny CoreGraphics helper that prints every normal on-screen window's rectangle
as JSON (front-to-back, so hidden parts of edges can be excluded). The pet polls it
on a background thread ~3×/s. It's compiled already; to rebuild:

```sh
clang -O2 -framework CoreGraphics -framework CoreFoundation \
  helpers/window_list.c -o helpers/window_list
```

On Windows the equivalent helper is
[helpers/window_list_win.c](helpers/window_list_win.c) (Win32 `EnumWindows` +
DWM extended frame bounds, same JSON output), built with MinGW:

```sh
gcc -O2 helpers/window_list_win.c -o helpers/window_list.exe
```

No permissions are needed for windows — window *bounds* are public; only window
titles would require screen recording permission, and we don't read those. If the
helper binary is missing the pet still runs, but only knows about the Dock line.

**Desktop icons** are read from Finder via
[helpers/desktop_icons.applescript](helpers/desktop_icons.applescript) (icons
aren't real windows, so the CoreGraphics helper can't see them). The first run
triggers a one-time macOS prompt asking to let the app control Finder — approve
it to enable icon perching; if denied, icons are simply ignored. Icons hidden
behind app windows, or via Finder's `CreateDesktop=false` pref, are not landable.

The Dock is located via Godot's usable-screen rect (its bottom edge is the Dock's
top), so the "Dock platform" spans the full screen width at Dock height.

Debug env vars: `PET_DEBUG=1` logs state, form, current animation, icon-poll
status, and detected ledges once per second; `PET_SPAWN="x,y"` drops the pet at
a chosen position (in physical pixels); `PET_PLAY=1` starts in play mode;
`PET_FORM=eevee|snorlax|fletchling` picks the starting character (`cat`/`parrot`
still work as aliases); `PET_NAP=1` naps at the first opportunity;
`PET_SNAP=/path.png` saves one viewport snapshot (plus
the Pokéball window's view as `…-home.png`) `PET_SNAP_AT` seconds after launch
(default ~2 s, minimum 0.5); `PET_NO_ICONS=1` skips the Finder desktop-icon poll — useful in
contexts where the Finder-automation permission prompt can't be answered, since
an unanswered prompt blocks the whole poll thread (ledges and bridge commands
stop updating).

## Tuning

All the personality knobs are constants at the top of [pet.gd](pet.gd):
`SPRITE_SCALE` (character size), `WANDER_SPEED`, `HUNGRY_AFTER`,
`NAP_MIN`/`NAP_MAX`, nap lengths, jump/flight speeds. If you change
`SPRITE_SCALE` much, grow or shrink the window size in
[project.godot](project.godot) to match.
