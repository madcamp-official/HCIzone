/*
 * 03_cliff_test — 낭떠러지 감지 (KY-032, 단일)
 * ---------------------------------------------------------------------------
 * 아래를 향한 IR 근접센서 1개로 책상 끝을 감지.
 * 핀맵 (통합 배치도): KY-032 OUT = A0 (아날로그 핀을 디지털로 사용)
 *
 * 대부분 모듈: 바닥 감지=LOW, 허공(반사 없음)=HIGH → 낭떠러지=HIGH.
 * 모듈이 반대로 동작하면 CLIFF_DETECTED_LEVEL 을 LOW 로 바꿀 것.
 */

const uint8_t PIN_CLIFF = A0;
const int CLIFF_DETECTED_LEVEL = HIGH;

bool isCliff() { return digitalRead(PIN_CLIFF) == CLIFF_DETECTED_LEVEL; }

void setup() {
  pinMode(PIN_CLIFF, INPUT);
  Serial.begin(9600);
  Serial.println(F("=== cliff test (KY-032, OUT=A0) ==="));
  Serial.println(F("책상 위=floor, 끝 너머로 내밀면 CLIFF 떠야 정상"));
}

void loop() {
  Serial.print(F("raw="));
  Serial.print(digitalRead(PIN_CLIFF));   // 0/1 원시값 (극성 확인용)
  Serial.print(F("  state="));
  Serial.println(isCliff() ? F("CLIFF") : F("floor"));
  delay(200);
}
