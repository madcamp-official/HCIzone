// Minimal serial bridge for the desktop-pet's on_enter_home / on_exit_home
// hooks. Turns an LED on when the cat comes home, off when it leaves.
//
// Wiring: works with no wiring at all using the board's onboard LED
// (LED_BUILTIN). For a more visible external LED instead, connect its long
// leg (anode) through a ~220ohm resistor to pin 13, and its short leg
// (cathode) to GND, and change LED_PIN below to 13.
//
// Protocol: one line per command over serial at 9600 baud — "ON\n" or
// "OFF\n". See ../../arduino_led.sh, the shell side of this bridge.

const int LED_PIN = LED_BUILTIN;
String line;

void setup() {
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  Serial.begin(9600);
}

void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      line.trim();
      if (line == "ON") {
        digitalWrite(LED_PIN, HIGH);
      } else if (line == "OFF") {
        digitalWrite(LED_PIN, LOW);
      }
      line = "";
    } else if (c != '\r') {
      line += c;
    }
  }
}
