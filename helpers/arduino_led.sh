#!/bin/bash
# Turns an LED on an Arduino running arduino/led_bridge/led_bridge.ino on or
# off over USB-serial. macOS only (uses `stty -f`).
#
# Usage: arduino_led.sh on|off
#
# Port is auto-detected among the usual USB-serial device names; override
# with ARDUINO_PORT=/dev/cu.xxxx. Baud override: ARDUINO_BAUD=9600.
# If no Arduino is found, this exits 0 and just prints a note — safe to call
# from a hook whether or not a board is plugged in.

set -euo pipefail

cmd="${1:-}"
if [[ "$cmd" != "on" && "$cmd" != "off" ]]; then
  echo "usage: $(basename "$0") on|off" >&2
  exit 2
fi

port="${ARDUINO_PORT:-}"
if [[ -z "$port" ]]; then
  for candidate in /dev/cu.usbmodem* /dev/cu.usbserial* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART*; do
    if [[ -e "$candidate" ]]; then
      port="$candidate"
      break
    fi
  done
fi

if [[ -z "$port" ]]; then
  echo "arduino_led: no Arduino serial port found (set ARDUINO_PORT to override) — skipping"
  exit 0
fi

baud="${ARDUINO_BAUD:-9600}"
stty -f "$port" "$baud" cs8 -cstopb -parenb raw -echo

# Opening the port resets most Arduino boards (DTR toggle on open); give the
# bootloader a moment to finish before sending anything, or the first
# command after a fresh reset gets dropped.
exec 3>"$port"
sleep 2
if [[ "$cmd" == "on" ]]; then
  printf 'ON\n' >&3
else
  printf 'OFF\n' >&3
fi
exec 3>&-

label=$(printf '%s' "$cmd" | tr '[:lower:]' '[:upper:]')
echo "arduino_led: sent $label to $port"
