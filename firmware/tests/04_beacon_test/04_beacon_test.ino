/*
 * 04_beacon_test — IR 비콘 방향 탐지 (KY-022 좌/우)
 * ---------------------------------------------------------------------------
 * 수신모듈(KY-022/VS1838B 등)은 38kHz 유효신호가 들어오면 출력이 LOW로 떨어진다.
 * 좌/우 핀을 고정 간격으로 샘플링해 LOW 히트수를 세고 '비율'로 방향을 판정.
 * 핀맵 (통합 배치도): 비콘 좌 = D7,  비콘 우 = D8 (폴링)
 *
 * 출력: hitL / hitR / 방향(LEFT / RIGHT / AHEAD / none)
 */

const uint8_t PIN_BEACON_L = 7;
const uint8_t PIN_BEACON_R = 8;

const unsigned long BEACON_WINDOW_MS = 200;  // 샘플링 창
const unsigned int  BEACON_SAMPLE_US = 200;  // 샘플 간격 → 창당 약 1000 샘플
const unsigned int  BEACON_MIN_HITS  = 20;   // 이보다 적으면 신호 없음
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
