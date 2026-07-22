/*
 * 09_ir_rx_debug — IR 수신 센서(KY-022) 원시 신호 디버깅
 * ---------------------------------------------------------------------------
 * 목적: main_robot.ino / 04_beacon_test.ino의 signalStrength()는 140ms 창에서
 * 2800번 샘플링해 "세기"를 계산하는 AGC 대응 로직이다. 이 검증된 로직 자체를
 * 의심할 필요는 지금 없다 — 대신 그 로직이 가정하는 모든 것(70ms 주기, AGC
 * 회복 등)을 걷어내고, "핀이 물리적으로 LOW가 되는 순간이 있기는 한지"만
 * 아무 가정 없이 최대한 빠르게 폴링해서 보여준다.
 *
 * 사용법:
 *   1) 로봇(수신기 D7/D8 연결된) 아두이노에 이 코드를 업로드
 *   2) 시리얼 모니터(9600bps) 열기 — 200ms마다 L/R 각각 "LOW 비율(%)"이 찍힘
 *   3) 먼저 아무 것도 없는 상태에서 기준선(보통 0%대) 확인
 *   4) 집 비콘을 켜고(H) 수신기 앞 5~10cm까지 가까이 대며 % 변화 관찰
 *
 * 판단 기준:
 *   - 비콘을 아무리 가까이 대도 계속 0%대 → 수신기에 신호가 전혀 안 들어옴.
 *     배선(S/VCC/GND), 전원, 센서 고장 쪽 문제. → 아래 "교차 검증"으로 좁힐 것.
 *   - 비콘을 가까이 댈 때 %가 순간적으로라도 오름(수 %~수십 %) → 신호는
 *     물리적으로 도달하고 있음. 거리/각도/거리별 임계값 튜닝 문제로 좁혀짐.
 *
 * ── 교차 검증(매우 중요, 코드 없이 가능) ────────────────────────────────────
 * 집 비콘 대신 아무 IR 리모컨(TV, 에어컨 등)을 수신기 5~10cm 앞에서 아무
 * 버튼이나 눌러 보십시오. 대부분의 가전 리모컨도 36~40kHz 대역이라 KY-022가
 * 반응합니다.
 *   - 리모컨엔 %가 반응하는데 집 비콘엔 무반응 → "수신기는 정상, 송신기(집
 *     비콘) 쪽이 문제" (LED 손상/배선/코드 확인으로 좁혀짐)
 *   - 리모컨에도 전혀 반응 없음 → "수신기 자체가 문제" (D7/D8 배선, KY-022
 *     전원(VCC/GND), 모듈 고장 가능성)
 * 이 교차 검증 하나로 송신기 문제와 수신기 문제를 확실하게 구분할 수 있습니다.
 */

const uint8_t RX_L = 7;   // 통합 핀맵과 동일
const uint8_t RX_R = 8;

// KY-022가 38kHz 버스트 수신 시 내는 출력. 극성이 반대인 개체면 HIGH로 변경.
const uint8_t IR_ACTIVE_STATE = LOW;

const unsigned long WINDOW_MS = 200;  // 이 주기로 결과를 갱신 출력

unsigned long windowStart = 0;
unsigned long sampleCount = 0;
unsigned long lowCountL = 0, lowCountR = 0;

void setup() {
  pinMode(RX_L, INPUT);
  pinMode(RX_R, INPUT);
  Serial.begin(9600);
  Serial.println(F("=== IR RX raw debug (AGC/타이밍 가정 없이 원시 측정) ==="));
  Serial.println(F("200ms마다 L/R 각각 LOW 비율(%)을 출력합니다."));
  Serial.println(F("먼저 기준선(0%대)을 확인한 뒤, 비콘/리모컨을 가까이 대며 비교하세요."));
  windowStart = millis();
}

void loop() {
  // 지연 없이 최대한 빠르게 반복 폴링 — 짧은 펄스도 놓치지 않기 위함.
  if (digitalRead(RX_L) == IR_ACTIVE_STATE) lowCountL++;
  if (digitalRead(RX_R) == IR_ACTIVE_STATE) lowCountR++;
  sampleCount++;

  unsigned long now = millis();
  if (now - windowStart >= WINDOW_MS) {
    float pctL = sampleCount ? (100.0f * (float)lowCountL / (float)sampleCount) : 0.0f;
    float pctR = sampleCount ? (100.0f * (float)lowCountR / (float)sampleCount) : 0.0f;

    Serial.print(F("샘플="));
    Serial.print(sampleCount);
    Serial.print(F("  L="));
    Serial.print(pctL, 1);
    Serial.print(F("%  R="));
    Serial.print(pctR, 1);
    Serial.println(F("%"));

    sampleCount = 0;
    lowCountL = 0;
    lowCountR = 0;
    windowStart = now;
  }
}
