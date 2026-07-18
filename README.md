# Desktop Pet

A tiny desktop cat that lives in a transparent, always-on-top window on your screen.
Drawn entirely in code — no image assets.

## Run it

Requires **Godot 4.2+** (no install here yet: `brew install --cask godot`).

- Open the Godot project manager, **Import** this folder, and press **F5**, or
- from a terminal: `godot --path /path/to/desktop-pet`

## Controls

| Input | What happens |
|---|---|
| Left-drag | Carry the cat anywhere on screen (its feet dangle) |
| Left-click (no drag) | Boop — a heart floats up; wakes it from a nap |
| Right-click | Feed it a cookie |
| Middle-click or `P` | Toggle play mode: it chases your cursor |
| `B` | Toggle bird mode: becomes a parrot that flies instead of jumps |
| Click the house | Send the cat home / let it back out |
| `H` | Same as clicking the house |
| Drag the house | Slide it along the Dock line |
| `Esc` / `Q` | Quit |

## Behavior

- **Walks on your windows, desktop icons, and the Dock.** The pet has gravity:
  it falls until it lands on the top edge of another app's window, a visible
  desktop icon, or the Dock line, and paces along whatever it landed on. It
  rides windows that move, falls (with a squish) when its perch is closed or
  slid out from under it, and sometimes deliberately walks off an edge. Drag it
  and drop it onto a window or icon to perch it there. Its shadow rests on the
  ledge it's standing on — clipped to the ledge's edges, never cut off by the
  Dock, and absent mid-air.
- **Play mode** (middle-click or `P`): it sprints after your cursor along its
  ledge, pounces into the air when the cursor is overhead, chases right off
  edges, and after ~35 s it's all tired out and will nap soon.
- **Hops around on its own.** Every so often it spots another ledge in jumping
  range — a window edge, a desktop icon, sometimes the Dock — crouches, and makes
  a proper ballistic leap onto it (it has cartoon legs: up to ~950 px straight
  up). Icons make natural stepping stones from the Dock up to window tops.
- **Wanders** left and right along its current ledge now and then.
- **Naps** after 25–60 s awake: eyes close, it squashes down, z's float up. Naps last
  12–25 s unless you wake it.
- **Gets hungry** after ~45 s without food: mouth turns sad and it daydreams about
  cookies in a thought bubble. Feeding resets hunger.
- **Bird mode** (`B`): shapeshifts into a green parrot. Sleep, play mode, feeding,
  wandering, and going home all behave exactly the same — the only difference is
  how it crosses gaps between ledges. As a cat it jumps (a crouch, then a
  ballistic leap under gravity); as a parrot it flies (a smooth, gravity-free
  glide straight to the target, with a wing flap and a little bob), so falling
  off a vanished ledge or being dropped mid-air also turns into a flight to the
  nearest perch instead of a plummet. Toggling mid-air works too — it's a
  mid-flight shapeshift.

## The home, and the virtual ↔ real bridge

A little house (its own transparent window, drawn in [home.gd](home.gd)) sits on
the Dock line; drag it sideways to place it. Click it (or press `H`) and the cat
travels there — walking its ledge, marching off edges, falling, resuming — then
shrinks into the doorway and vanishes. While it's inside, amber eyes blink from
the dark door and the house window glows. Click again to let it back out. It also
wanders home by itself every few minutes, and its roof is a hoppable perch.

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

Debug env vars: `PET_DEBUG=1` logs state, form, icon-poll status, and detected
ledges once per second; `PET_SPAWN="x,y"` drops the pet at a chosen position (in
physical pixels); `PET_PLAY=1` starts in play mode; `PET_FORM=parrot` starts as
a parrot.

## Tuning

All the personality knobs are constants at the top of [pet.gd](pet.gd):
`WANDER_SPEED`, `HUNGRY_AFTER`, `NAP_MIN`/`NAP_MAX`, nap lengths, and the colors.
