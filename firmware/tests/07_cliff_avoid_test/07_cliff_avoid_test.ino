/*
 * 07_cliff_avoid_test — 모터 + 낭떠러지(KY-032) 결합
 * ---------------------------------------------------------------------------
 * main_robot.ino 의 모터/낭떠러지 로직·핀·상수를 그대로 참조한 축소판 테스트.
 * 동작: 전진 → 책상 끝(낭떠러지) 감지 → 잠깐 멈춤 → 뒤로 물러남 → 회전 → 다시 전진.
 *
 * 핀맵 (통합 배치도):
 *   좌 채널 : EN=11(PWM) IN1=10 IN2=9
 *   우 채널 : EN=6(PWM)  IN1=5  IN2=3
 *   낭떠러지: KY-032 OUT = A0 (디지털로 사용)
 *
 * ※ 낭떠러지는 책상 끝이라 회전 전에 "뒤로 물러나기"가 안전상 필수.
 *   그 자리에서 바로 돌면 바퀴가 끝 너머로 넘어갈 수 있음.
 */

// ---- 모터 핀 ----
const uint8_t L_EN = 11, L_IN1 = 10, L_IN2 = 9;   // 좌 채널
const uint8_t R_EN = 6,  R_IN1 = 5,  R_IN2 = 3;   // 우 채널

// ---- 낭떠러지 핀 ----
const uint8_t PIN_CLIFF = A0;

// ---- 튜닝 상수 (main_robot 과 동일) ----
const uint8_t  SPEED_CRUISE = 150;   // 주행 / 후진
const uint8_t  SPEED_TURN   = 170;   // 회전
const uint16_t BACKUP_MS    = 350;   // 낭떠러지에서 물러나는 시간
const uint16_t TURN_MS      = 400;   // 회전 시간(실측 보정)
const uint16_t PAUSE_MS     = 200;   // 낭떠러지 앞 "잠깐 멈춤" 시간

// 낭떠러지 극성: 바닥이 있을 때 KY-032 출력. 낭떠러지 = 반대값.
// 모듈이 반대로 동작하면 이 값만 HIGH 로 바꿀 것.
const uint8_t CLIFF_SURFACE_STATE = LOW;

// 좌/우 채널 속도 보정 (main_robot 과 동일). 100 = 보정 없음.
const uint16_t TRIM_LEFT  = 100;
const uint16_t TRIM_RIGHT = 100;

// ─────────────────────────────────────────────────────────────────────────
//  모터 제어 (스키드 스티어). speed: -255~255 (음수 = 후진)
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

void stopMotors()     { drive(0, 0); }
void forward(int s)   { drive(s, s); }
void backward(int s)  { drive(-s, -s); }
void spinRight(int s) { drive(s, -s); }   // 좌 전진 / 우 후진 → 제자리 우회전

// ─────────────────────────────────────────────────────────────────────────
//  낭떠러지 감지 (main_robot 과 동일)
// ─────────────────────────────────────────────────────────────────────────
bool cliffDetected() {
  return digitalRead(PIN_CLIFF) != CLIFF_SURFACE_STATE;
}

void setup() {
  uint8_t outs[] = {L_EN, L_IN1, L_IN2, R_EN, R_IN1, R_IN2};
  for (uint8_t i = 0; i < sizeof(outs); i++) pinMode(outs[i], OUTPUT);
  pinMode(PIN_CLIFF, INPUT);
  stopMotors();

  Serial.begin(9600);
  Serial.println(F("=== cliff avoid test (motor + KY-032) ==="));
  delay(2000);   // 로봇 내려놓을 시간
}

void loop() {
  if (cliffDetected()) {
    // 낭떠러지: 잠깐 멈춤 → 뒤로 물러남 → 회전
    Serial.println(F("!! CLIFF -> stop, back up, turn"));
    stopMotors();
    delay(PAUSE_MS);
    backward(SPEED_CRUISE);
    delay(BACKUP_MS);
    stopMotors();
    delay(80);
    spinRight(SPEED_TURN);
    delay(TURN_MS);
    stopMotors();
    delay(80);
  } else {
    // 바닥 있음: 전진
    forward(SPEED_CRUISE);
  }

  delay(20);   // 낭떠러지 자주 확인(전진 중 반응성 확보)
}
