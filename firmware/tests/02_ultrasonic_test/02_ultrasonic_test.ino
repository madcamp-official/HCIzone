/*
 * 02_ultrasonic_test — HC-SR04 거리 측정
 * ---------------------------------------------------------------------------
 * 핀맵 (통합 배치도): TRIG = D13, ECHO = D12 (ECHO 직결)
 * 시리얼(9600)에 거리(cm)와 장애물 여부 출력.
 */

const uint8_t PIN_TRIG = 13;
const uint8_t PIN_ECHO = 12;

const int OBSTACLE_CM = 12;                     // 이 거리 이하면 장애물
const unsigned long ULTRASONIC_INTERVAL_MS = 60;

long readDistanceCm() {
  digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  unsigned long dur = pulseIn(PIN_ECHO, HIGH, 25000UL);  // 25ms ≈ 4m
  if (dur == 0) return 999;                              // 반향 없음(트여 있음)
  return (long)(dur * 0.0343 / 2.0);
}

void setup() {
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  digitalWrite(PIN_TRIG, LOW);
  Serial.begin(9600);
  Serial.println(F("=== ultrasonic test (TRIG=D13, ECHO=D12) ==="));
}

void loop() {
  long cm = readDistanceCm();
  Serial.print(F("dist(cm)="));
  Serial.print(cm);
  Serial.print(F("  obstacle="));
  Serial.println(cm <= OBSTACLE_CM ? F("YES") : F("no"));
  delay(ULTRASONIC_INTERVAL_MS);
}
