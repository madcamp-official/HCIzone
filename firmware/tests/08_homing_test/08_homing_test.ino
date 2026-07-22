/*
 * 08_homing_test — 모터 + IR 비콘 (귀가)  [04_beacon_test 기반]
 * ---------------------------------------------------------------------------
 * 04_beacon_test 의 검증된 감지 방식(signalStrength: 넓은 창에서 LOW 샘플 수를
 * 세어 좌/우 세기 비교)을 그대로 쓰고, 거기에 모터 조향을 붙인 귀가 테스트.
 *
 * 핀맵 (통합 배치도):
 *   좌 채널 : EN=11(PWM) IN1=10 IN2=9
 *   우 채널 : EN=6(PWM)  IN1=5  IN2=3
 *   비콘 수신: 좌 = D7,  우 = D8
 *
 * 동작 (측정→판단→이동을 반복):
 *   1) 잠깐 멈춤 → 좌/우 세기 측정 (모터 노이즈 방지 위해 정지 상태에서 측정)
 *   2) 신호 없음        → 제자리 회전하며 탐색
 *   3) 좌가 셈           → 왼쪽으로 회전(한 스텝)
 *   4) 우가 셈           → 오른쪽으로 회전(한 스텝)
 *   5) 좌우 비슷(정면)   → 앞으로 한 걸음 전진
 *   6) 양쪽 다 충분히 셈 → "도착"으로 보고 정지
 *
 * ※ 별도 보드에 05a_ir_beacon_transmitter(비콘)를 켜 두고 테스트할 것.
 * ※ 도착 임계 ARRIVE_STRENGTH 는 시리얼에 찍히는 L/R 값을 보고 실측 튜닝.
 */

// ---- 모터 핀 ----
const uint8_t L_EN = 11, L_IN1 = 10, L_IN2 = 9;   // 좌 채널
const uint8_t R_EN = 6,  R_IN1 = 5,  R_IN2 = 3;   // 우 채널

// ---- 비콘 수신 핀 (04_beacon_test 와 동일) ----
const int RX_L = 7, RX_R = 8;

// ---- 비콘 감지 상수 (04_beacon_test 와 동일) ----
const int SAMPLES    = 2800;  // 약 140ms (50us x 2800) - 비콘 주기(70ms)의 2배
const int NO_SIGNAL  = 25;    // 좌·우 각각 이 값 미만이면 신호 없음
const int CENTER_TOL = 30;    // 좌우 차이가 이보다 작으면 정면

// ---- 귀가 도착 판정 (★ 실측 튜닝) ----
// 비콘에 가까워질수록 L/R 값이 커진다. 양쪽이 이 값 이상이면 "집 근접"으로 판정.
const int ARRIVE_STRENGTH = 500;

// ---- 모터 속도/이동 시간 ----
const uint8_t  SPEED_HOME  = 130;   // 전진 속도(천천히)
const uint8_t  SPEED_TURN  = 170;   // 회전 속도
const uint16_t MS_FORWARD_LEG = 300;  // 정면일 때 전진 한 걸음
const uint16_t MS_TURN_STEP   = 150;  // 방향 보정 한 스텝
const uint16_t MS_SEARCH_STEP = 200;  // 신호 없을 때 탐색 회전 한 스텝

// 좌/우 채널 속도 보정. 100 = 보정 없음.
const uint16_t TRIM_LEFT  = 100;
const uint16_t TRIM_RIGHT = 100;

bool arrived = false;

// ─────────────────────────────────────────────────────────────────────────
//  모터 제어 (스키드 스티어)
// ─────────────────────────────────────────────────────────────────────────
void sideDrive(uint8_t en, uint8_t in1, uint8_t in2, int speed, uint16_t trim) {
  int mag = speed;
  if (mag < 0) mag = -mag;
  mag = (int)(((uint32_t)mag * trim) / 100);
  if (mag > 255) mag = 255;
  if (speed > 0)      { digitalWrite(in1, HIGH); digitalWrite(in2, LOW); }
  else if (speed < 0) { digitalWrite(in1, LOW);  digitalWrite(in2, HIGH); }
  else                { digitalWrite(in1, LOW);  digitalWrite(in2, LOW); }
  analogWrite(en, (uint8_t)mag);
}

void drive(int left, int right) {
  sideDrive(L_EN, L_IN1, L_IN2, left,  TRIM_LEFT);
  sideDrive(R_EN, R_IN1, R_IN2, right, TRIM_RIGHT);
}

void stopMotors()            { drive(0, 0); }
void forward(int s)          { drive(s, s); }
void turnLeftInPlace(int s)  { drive(-s, s); }   // 좌 후진 / 우 전진 → 제자리 좌회전
void turnRightInPlace(int s) { drive(s, -s); }   // 좌 전진 / 우 후진 → 제자리 우회전

// ─────────────────────────────────────────────────────────────────────────
//  비콘 세기 측정 (04_beacon_test 와 동일)
// ─────────────────────────────────────────────────────────────────────────
int signalStrength(int pin) {
  int lowCount = 0;
  for (int i = 0; i < SAMPLES; i++) {
    if (digitalRead(pin) == LOW) lowCount++;
    delayMicroseconds(50);
  }
  return lowCount;
}

void setup() {
  uint8_t outs[] = {L_EN, L_IN1, L_IN2, R_EN, R_IN1, R_IN2};
  for (uint8_t i = 0; i < sizeof(outs); i++) pinMode(outs[i], OUTPUT);
  pinMode(RX_L, INPUT);
  pinMode(RX_R, INPUT);
  stopMotors();

  Serial.begin(9600);
  Serial.println(F("=== homing test (motor + beacon, 04 based) ==="));
  delay(2000);   // 로봇 내려놓을 시간
}

void loop() {
  if (arrived) { stopMotors(); return; }   // 도착 후 정지 유지(재시도하려면 리셋)

  // 1) 정지 상태에서 측정 (모터 노이즈 방지)
  stopMotors();
  delay(50);
  int left  = signalStrength(RX_L);
  int right = signalStrength(RX_R);

  Serial.print(F("L=")); Serial.print(left);
  Serial.print(F("  R=")); Serial.print(right);
  Serial.print(F("  -> "));

  // 2) 신호 없음 → 탐색 회전
  if (left < NO_SIGNAL && right < NO_SIGNAL) {
    Serial.println(F("NO SIGNAL: search-spin"));
    turnRightInPlace(SPEED_TURN);
    delay(MS_SEARCH_STEP);
    stopMotors();
    return;
  }

  // 3) 도착 판정 (양쪽 다 충분히 강함)
  if (left >= ARRIVE_STRENGTH && right >= ARRIVE_STRENGTH) {
    Serial.println(F(">>> ARRIVED: stop"));
    stopMotors();
    arrived = true;
    return;
  }

  // 4) 방향 조향
  int diff = left - right;
  if (abs(diff) < CENTER_TOL) {
    Serial.println(F("CENTER: forward"));
    forward(SPEED_HOME);
    delay(MS_FORWARD_LEG);
  } else if (diff > 0) {
    Serial.println(F("LEFT: turn left"));
    turnLeftInPlace(SPEED_TURN);
    delay(MS_TURN_STEP);
  } else {
    Serial.println(F("RIGHT: turn right"));
    turnRightInPlace(SPEED_TURN);
    delay(MS_TURN_STEP);
  }
  stopMotors();
}
