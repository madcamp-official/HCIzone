/*
 * 05_bluetooth_test — HC-06 통신 확인 (SoftwareSerial)
 * ---------------------------------------------------------------------------
 * 핀맵 (통합 배치도):
 *   D2 ← HC-06 TXD  (아두이노 RX)
 *   D4 → HC-06 RXD  (아두이노 TX, 1k/2k 전압분배)
 *
 * 동작:
 *   - 폰(블루투스 시리얼 앱)에서 보낸 문자를 USB 시리얼 모니터로 그대로 출력.
 *   - USB 시리얼 모니터에 입력한 문자를 HC-06 으로 그대로 전달(에코).
 *   양쪽 다 9600bps. HC-06 기본 속도가 9600 이 아니면 BT_BAUD 를 조정.
 */

#include <SoftwareSerial.h>

const uint8_t PIN_BT_RX = 2;   // ← HC-06 TXD
const uint8_t PIN_BT_TX = 4;   // → HC-06 RXD (전압분배)
const long BT_BAUD = 9600;

SoftwareSerial bt(PIN_BT_RX, PIN_BT_TX);

void setup() {
  Serial.begin(9600);
  bt.begin(BT_BAUD);
  Serial.println(F("=== HC-06 bridge test (RX=D2, TX=D4) ==="));
  Serial.println(F("폰->로봇: 여기 출력됨 / 모니터입력->로봇: HC-06으로 전달"));
}

void loop() {
  // HC-06 → USB 모니터
  while (bt.available()) {
    char c = bt.read();
    Serial.print(F("[BT] "));
    Serial.println(c);
  }
  // USB 모니터 → HC-06
  while (Serial.available()) {
    char c = Serial.read();
    bt.write(c);
  }
}
