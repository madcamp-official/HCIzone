/*
 * 04_beacon_test — IR 비콘 방향/세기 비교 (KY-022 x2, AGC 대응판)
 * ---------------------------------------------------------------------------
 * 검증된 05b_ir_receiver_test 와 로직·상수·구조를 동일하게 맞춘 버전.
 * 유일한 차이: 핀만 통합 배치도의 D7/D8 사용 (05b는 D2/D4 → HC-06과 충돌).
 *
 * 송신기(05a)가 "짧게 쏘고 길게 쉬는"(주기 70ms) 방식이므로, 측정 창을 넓혀
 * (약 140ms = 50us x 2800) 그 주기 안의 버스트를 확실히 잡는다. 이렇게 하면
 * 신호가 갑자기 0으로 죽는 AGC 문제가 완화된다.
 *
 * 배선(KY-022: S / 중앙+(VCC) / -(GND)):
 *   수신기 L : S -> 7 , VCC -> 5V , GND -> GND
 *   수신기 R : S -> 8 , VCC -> 5V , GND -> GND
 *
 * 원리: 수신 중 S가 LOW. 넓은 창에서 LOW 샘플 수를 세어 좌우 비교.
 *   (값이 작아지는 대신 안정적으로 유지됨. 절대값보다 L/R 비교를 볼 것)
 */

const int RX_L = 7, RX_R = 8;   // ★ 핀만 유지, 나머지는 05b와 동일
const int SAMPLES    = 2800;    // 약 140ms (50us x 2800) - 비콘 주기(70ms)의 2배
const int NO_SIGNAL  = 25;      // 이 값 미만이면 신호 없음
const int CENTER_TOL = 30;      // 좌우 차이가 이보다 작으면 정면

int signalStrength(int pin) {
  int lowCount = 0;
  for (int i = 0; i < SAMPLES; i++) {
    if (digitalRead(pin) == LOW) lowCount++;
    delayMicroseconds(50);
  }
  return lowCount;
}

void setup() {
  Serial.begin(9600);
  pinMode(RX_L, INPUT);
  pinMode(RX_R, INPUT);
  Serial.println("IR receiver direction test (AGC-safe) start");
}

void loop() {
  int left  = signalStrength(RX_L);
  int right = signalStrength(RX_R);

  Serial.print("L="); Serial.print(left);
  Serial.print("  R="); Serial.print(right);
  Serial.print("  -> ");

  if (left < NO_SIGNAL && right < NO_SIGNAL) {
    Serial.println("NO SIGNAL (신호 없음 - 재탐색)");
  } else {
    int diff = left - right;
    if (abs(diff) < CENTER_TOL) Serial.println("정면(CENTER)");
    else if (diff > 0)          Serial.println("집은 왼쪽 (turn LEFT)");
    else                        Serial.println("집은 오른쪽 (turn RIGHT)");
  }
}
