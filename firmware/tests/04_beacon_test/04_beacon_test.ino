/*
 * 04_beacon_test — IR 비콘 방향 탐지 (KY-022 좌/우)
 * ---------------------------------------------------------------------------
 * 수신모듈(KY-022/VS1838B 등)은 38kHz 유효신호가 들어오면 출력이 LOW로 떨어진다.
 * ※ 38kHz 복조는 수신칩이 하드웨어로 처리한다. 이 코드는 주파수를 다루지 않고
 *   핀의 LOW/HIGH만 세므로, 송신 주파수와 "코드"가 어긋날 일은 없다.
 *
 * 송신기(05a)와의 짝맞춤이 핵심:
 *   05a는 "약 10ms 버스트 + 60ms 휴식 = 주기 70ms"로 쏜다(AGC 회복용).
 *   따라서 측정 창은 그 주기를 확실히 덮도록 2배(≈140ms)로 잡아,
 *   창 안에 버스트가 최소 한 번은 들어오게 한다. (창이 좁으면 휴식 구간에
 *   걸려 신호를 통째로 놓쳐 값이 0으로 죽는다 = AGC 오인.)
 *
 * 좌/우 핀을 고정 간격으로 샘플링해 LOW 히트수를 세고 '비율'로 방향을 판정.
 * 핀맵 (통합 배치도): 비콘 좌 = D7,  비콘 우 = D8 (폴링)
 *   (참고: 05b 예제는 D2/D4를 썼으나, 그 핀은 HC-06과 충돌하므로 D7/D8 사용)
 *
 * 출력: hitL / hitR / 방향(LEFT / RIGHT / AHEAD / none)
 */

const uint8_t PIN_BEACON_L = 7;
const uint8_t PIN_BEACON_R = 8;

const unsigned long BEACON_WINDOW_MS = 140;  // 송신 주기(70ms)의 2배 — 버스트 확실히 포착
const unsigned int  BEACON_SAMPLE_US = 50;   // 샘플 간격(버스트 엔벨로프까지 촘촘히)
const unsigned int  BEACON_MIN_HITS  = 25;   // 이보다 적으면 신호 없음(05b와 동일)
const unsigned int  BEACON_DIFF_PCT  = 20;   // 큰 쪽 대비 이 % 이상 차이나야 방향 확정

// -2 신호없음 / -1 왼쪽 / 0 정면 / +1 오른쪽
int readBeaconDirection(unsigned int &hitL, unsigned int &hitR) {
  unsigned long t0 = millis();
  hitL = 0; hitR = 0;
  while (millis() - t0 < BEACON_WINDOW_MS) {
    if (digitalRead(PIN_BEACON_L) == LOW) hitL++;
    if (digitalRead(PIN_BEACON_R) == LOW) hitR++;
    delayMicroseconds(BEACON_SAMPLE_US);
  }
  unsigned int total = hitL + hitR;
  if (total < BEACON_MIN_HITS) return -2;
  unsigned int larger = (hitL > hitR) ? hitL : hitR;
  unsigned int diff   = (hitL > hitR) ? (hitL - hitR) : (hitR - hitL);
  if ((unsigned long)diff * 100UL >= (unsigned long)larger * BEACON_DIFF_PCT)
    return (hitL > hitR) ? -1 : +1;
  return 0;
}

void setup() {
  pinMode(PIN_BEACON_L, INPUT);
  pinMode(PIN_BEACON_R, INPUT);
  Serial.begin(9600);
  Serial.println(F("=== beacon test (L=D7, R=D8) ==="));
}

void loop() {
  unsigned int hitL, hitR;
  int dir = readBeaconDirection(hitL, hitR);
  Serial.print(F("hitL=")); Serial.print(hitL);
  Serial.print(F(" hitR=")); Serial.print(hitR);
  Serial.print(F(" -> "));
  switch (dir) {
    case -1: Serial.println(F("LEFT"));  break;
    case  0: Serial.println(F("AHEAD")); break;
    case +1: Serial.println(F("RIGHT")); break;
    default: Serial.println(F("none"));  break;
  }
  delay(300);
}
