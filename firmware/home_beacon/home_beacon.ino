/*
 * ============================================================================
 *  집(도크) IR 비콘 송신기 — home_beacon
 * ----------------------------------------------------------------------------
 *  Arduino Uno(별도 보드) · 적외선 LED(KY-005 또는 베어 LED+저항) · 38kHz 비콘
 *
 *  이 버전은 실제로 검증됐던 원본 05a_ir_beacon_transmitter.ino의 펄스 구조를
 *  그대로 재현하고, 그 위에 시리얼 H/S 제어만 얹은 것이다. 이전 버전은 12ms
 *  동안 반송파를 "끊김 없이" 계속 내보냈는데, 이것이 인식 실패의 핵심 원인이었다
 *  — 아래 설명 참고.
 *
 *  ── 왜 "연속 톤"이 아니라 "짧은 펄스 8번"인가 (매우 중요) ─────────────────
 *  VS1838B(KY-022) 같은 IR 수신칩은 진짜 리모컨처럼 짧은 펄스(수백 us)로 반송파가
 *  끊겼다 이어졌다 하는 신호를 전제로 설계되어 있다. 반송파를 한 번에 10ms 넘게
 *  "끊김 없이" 계속 내보내면, 수신칩의 AGC(자동 이득 조절)가 이를 비정상적인
 *  배경 신호로 보고 이득을 낮춰 출력을 그냥 HIGH(무신호)로 눌러버릴 수 있다.
 *  그래서 이 코드는 "600us 송신 + 600us 휴식"을 8번 반복해(패킷 하나 ≈9.6ms)
 *  패킷 "안에서도" 계속 반송파를 끊어준다. 이후 60ms 더 쉬어 AGC를 완전히
 *  회복시키고 다음 패킷을 보낸다. 전체 주기 9.6+60≈70ms — 로봇 측
 *  signalStrength() 수신 창(140ms = 이 주기의 정확히 2배)과 04_beacon_test.ino
 *  주석의 "70ms"에 정밀하게 맞춘 값이다. 이 타이밍은 절대 임의로 바꾸지 말 것.
 *
 *  ── 시리얼 명령 (9600bps, Arduino IDE 시리얼 모니터) ────────────────────────
 *     'H' / 'h' → 비콘 켜기 (패킷 반복 송출 시작)
 *     'S' / 's' → 비콘 끄기
 *     '?'       → 현재 상태 출력
 *  전원 인가 시 기본은 꺼진 상태 — 'H'를 입력해야 송출을 시작한다.
 *  명령은 매 루프 최상단(패킷과 패킷 사이)에서만 확인하므로, 켜짐 상태에서는
 *  최대 한 패킷 주기(~70ms) 이내에 반영된다. 8펄스짜리 패킷 내부의 정밀한
 *  600us on/off 타이밍은 절대 건드리지 않는다(시리얼 폴링을 그 안에 넣지 않음).
 *
 *  ── 배선 (현재: 저항 없이 직결) ─────────────────────────────────────────────
 *     IR LED 긴다리(+, 애노드)  ──────────── 아두이노 D3
 *     IR LED 짧은다리(-, 캐소드) ──────────  GND
 *  KY-005 모듈이면 S핀=D3, -핀=GND.
 *
 *  ⚠ 경고: 직렬 저항이 없으면 (5V-LED순방향전압)을 핀 내부저항만으로 나눈
 *  전류가 흐르는데, 대략 100mA대까지 흐를 수 있다. ATmega328P 핀의 절대 최대
 *  정격은 40mA(권장 20mA)라 이 상태가 반복되면 D3 핀이 열화·손상될 수 있다.
 *  이는 소프트웨어로 제한할 수 없는 하드웨어적 한계이며(옴의 법칙), 그렇다고
 *  아래 펄스 타이밍을 줄여서 "완화"하면 검증된 수신 감지 파형이 깨진다 — 그래서
 *  일부러 그런 시도는 하지 않았다. 100Ω~1kΩ 사이 아무 저항이라도 직렬로 넣으면
 *  이 위험이 사실상 사라지고 밝기/사거리엔 거의 영향이 없으니, 가능하면 넣을 것.
 *  ※ 적외선은 안 보임 — 온보드 LED(D13)가 패킷마다(약 70ms 주기) 짧게
 *    깜빡이면 정상 송출 중이라는 뜻. 또는 휴대폰 카메라로 LED를 비춰 보라색
 *    깜빡임을 확인해도 된다.
 *
 *  ── 그래도 인식이 안 되면 ───────────────────────────────────────────────────
 *  로봇 쪽을 firmware/tests/04_beacon_test.ino로 임시 교체해 L/R 원시값을 직접
 *  관찰할 것. 값이 계속 0이면 배선/전원 문제, 낮게라도 뜨면 거리·각도·주변
 *  광원(형광등/직사광선) 간섭을 의심할 것.
 * ============================================================================
 */

const uint8_t IR_LED     = 3;            // 반송파 출력 핀 (원본과 동일)
const uint8_t STATUS_LED = LED_BUILTIN;  // 패킷 송출 중 깜빡임(육안 확인용)

const unsigned int  IR_CARRIER_HZ     = 38000;  // KY-022/VS1838B 대역
const unsigned int  PULSE_ON_US       = 600;    // 펄스 하나의 송신 길이
const unsigned int  PULSE_OFF_US      = 600;    // 펄스 사이 휴식(패킷 내부)
const uint8_t        PULSES_PER_PACKET = 8;     // 패킷 하나 = 8펄스 (≈9.6ms)
const unsigned long  PACKET_REST_MS    = 60;    // 패킷 뒤 휴식(AGC 회복). 총 주기 ≈70ms

bool beaconOn = false;

// 펄스 하나: 반송파 on(onUS) -> off(offUS). 원본과 동일한 블로킹 구현 —
// 이 함수 안에서는 시리얼을 확인하지 않는다(600us 단위 타이밍을 지키기 위해).
void pulse(unsigned int onUS, unsigned int offUS) {
  tone(IR_LED, IR_CARRIER_HZ);
  delayMicroseconds(onUS);
  noTone(IR_LED);
  delayMicroseconds(offUS);
}

// 패킷 하나 = 펄스 8번 (원본의 burst() 8회 호출과 동일한 파형).
void sendPacket() {
  digitalWrite(STATUS_LED, HIGH);
  for (uint8_t i = 0; i < PULSES_PER_PACKET; i++) pulse(PULSE_ON_US, PULSE_OFF_US);
  digitalWrite(STATUS_LED, LOW);
}

void handleSerial() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    switch (c) {
      case 'H': case 'h':
        beaconOn = true;
        Serial.println(F("BEACON ON (packet 10ms / period 70ms)"));
        break;
      case 'S': case 's':
        beaconOn = false;
        digitalWrite(STATUS_LED, LOW);
        Serial.println(F("BEACON OFF"));
        break;
      case '?':
        Serial.print(F("STATE="));
        Serial.println(beaconOn ? F("ON") : F("OFF"));
        break;
      default: break;  // 개행 등 기타 문자는 무시
    }
  }
}

void setup() {
  pinMode(IR_LED, OUTPUT);
  digitalWrite(IR_LED, LOW);
  pinMode(STATUS_LED, OUTPUT);
  digitalWrite(STATUS_LED, LOW);

  Serial.begin(9600);
  Serial.println(F("Home IR Beacon ready. Cmds: H=on  S=off  ?=status"));
  Serial.println(F("Press 'H' to start the beacon."));
  // 기본은 꺼짐 — 'H' 입력 시 발사 시작.
}

void loop() {
  handleSerial();          // 명령은 패킷 "사이"에서만 반영 (펄스 타이밍 보호)
  if (beaconOn) {
    sendPacket();           // 8 x (600us on + 600us off) ≈ 9.6ms
    delay(PACKET_REST_MS);  // AGC 회복용 60ms 휴식 → 총 주기 ≈70ms
  }
}
