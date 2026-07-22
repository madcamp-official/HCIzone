/*
 * 10_ir_tx_selftest — 집 비콘 송신부(KY-005/IR LED) 단독 점검
 * ---------------------------------------------------------------------------
 * home_beacon.ino의 실제 패킷(600us on/off x8, 70ms 주기)은 너무 빨라서
 * 휴대폰 카메라나 육안으로 "제대로 나오는지"를 확인하기 어렵다. 이 코드는
 * 그 복잡한 타이밍을 완전히 걷어내고 "1초 켜짐 / 1초 꺼짐"만 아주 천천히,
 * 확실하게 반복한다 — D13과 실제 IR LED 상태를 사람이 눈으로 정확히
 * 맞춰보기 위한 용도다.
 *
 * 사용법:
 *   1) 이 코드를 집 비콘 아두이노에 업로드 (배선은 home_beacon.ino와 동일:
 *      IR LED -> D3, GND -> GND)
 *   2) D13(온보드 LED)이 1초 간격으로 켜짐/꺼짐을 반복하는지 확인
 *      -> 이건 무조건 보여야 한다. 안 보이면 코드 업로드/보드 자체 문제.
 *   3) 휴대폰 카메라로 IR LED를 비추고, D13이 켜지는 바로 그 순간에
 *      카메라 화면에도 보라색/하얀 빛이 함께 켜지는지 확인
 *
 * 판단 기준:
 *   - D13은 정상 깜빡이는데 카메라엔 전혀 안 보임
 *       → IR LED 자체 손상, 또는 D3 핀 손상, 또는 배선(극성) 문제.
 *         (직전에 저항 없이 직결했다면 이 손상 가능성을 우선 의심할 것)
 *   - D13도 카메라도 둘 다 반응 없음
 *       → 코드가 안 올라갔거나 전원 문제일 가능성 (드문 경우)
 *   - 둘 다 정상 동작 → 송신부 하드웨어는 살아있음. 문제는 09_ir_rx_debug로
 *     넘어가 수신측/타이밍 쪽에서 찾을 것.
 */

const uint8_t IR_LED     = 3;            // home_beacon.ino와 동일 핀
const uint8_t STATUS_LED = LED_BUILTIN;

const unsigned int IR_CARRIER_HZ = 38000;

void setup() {
  pinMode(IR_LED, OUTPUT);
  digitalWrite(IR_LED, LOW);
  pinMode(STATUS_LED, OUTPUT);
  digitalWrite(STATUS_LED, LOW);

  Serial.begin(9600);
  Serial.println(F("=== IR TX selftest: 1초 ON / 1초 OFF 반복 ==="));
  Serial.println(F("D13과 휴대폰 카메라로 본 IR LED가 같은 타이밍에 켜지는지 확인하세요."));
}

void loop() {
  digitalWrite(STATUS_LED, HIGH);
  tone(IR_LED, IR_CARRIER_HZ);
  Serial.println(F("ON"));
  delay(1000);

  digitalWrite(STATUS_LED, LOW);
  noTone(IR_LED);
  Serial.println(F("OFF"));
  delay(1000);
}
