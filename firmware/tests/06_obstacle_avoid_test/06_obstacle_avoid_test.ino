/*
 * 06_obstacle_avoid_test — 모터 + 초음파 결합 (장애물 회피)
 * ---------------------------------------------------------------------------
 * main_robot.ino 의 모터/초음파 로직·핀·상수를 그대로 참조한 축소판 테스트.
 * 동작: 전진 → 앞에 장애물 감지 → 잠깐 멈춤 → 회전(방향 전환) → 다시 전진.
 *
 * 핀맵 (통합 배치도):
 *   좌 채널: EN=11(PWM) IN1=10 IN2=9
 *   우 채널: EN=6(PWM)  IN1=5  IN2=3
 *   초음파 : TRIG=D13, ECHO=D12
 *
 * ※ 이 테스트는 낭떠러지 센서가 없으므로 회피 동작 중 delay() 사용이 안전하다.
 *   (실주행 펌웨어 main_robot 은 낭떠러지 최우선 때문에 비차단으로 구성됨.)
 */

// ---- 모터 핀 ----
const uint8_t L_EN = 11, L_IN1 = 10, L_IN2 = 9;   // 좌 채널
const uint8_t R_EN = 6,  R_IN1 = 5,  R_IN2 = 3;   // 우 채널

// ---- 초음파 핀 ----
const uint8_t PIN_TRIG = 13;
const uint8_t PIN_ECHO = 12;

// ---- 튜닝 상수 (main_robot 과 동일) ----
const uint8_t  SPEED_CRUISE = 150;   // 주행
const uint8_t  SPEED_TURN   = 170;   // 회전
const uint16_t OBSTACLE_CM  = 15;    // 이 거리 이하면 장애물
const uint16_t TURN_MS      = 400;   // 회전 시간(실측 보정)
const uint16_t PAUSE_MS     = 250;   // 장애물 앞 "잠깐 멈춤" 시간
const uint32_t ECHO_TIMEOUT_US = 8000;   // ~1.3m. pulseIn 블로킹 상한

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
void spinRight(int s) { drive(s, -s); }   // 좌 전진 / 우 후진 → 제자리 우회전

// ─────────────────────────────────────────────────────────────────────────
//  초음파 거리 측정 (main_robot 과 동일한 방식)
// ─────────────────────────────────────────────────────────────────────────
uint16_t readDistanceCm() {
  digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  uint32_t us = pulseIn(PIN_ECHO, HIGH, ECHO_TIMEOUT_US);
  if (us == 0) return 999;               // 타임아웃 = 반사 없음(트여 있음)
  return (uint16_t)(us / 58UL);          // 왕복 → cm
}

void setup() {
  uint8_t outs[] = {L_EN, L_IN1, L_IN2, R_EN, R_IN1, R_IN2, PIN_TRIG};
  for (uint8_t i = 0; i < sizeof(outs); i++) pinMode(outs[i], OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  digitalWrite(PIN_TRIG, LOW);
  stopMotors();

  Serial.begin(9600);
  Serial.println(F("=== obstacle avoid test (motor + ultrasonic) ==="));
  delay(2000);   // 로봇 내려놓을 시간
}

void loop() {
  uint16_t cm = readDistanceCm();
  Serial.print(F("dist(cm)="));
  Serial.print(cm);

  if (cm <= OBSTACLE_CM) {
    // 장애물: 잠깐 멈춘 뒤 회전해서 방향 전환
    Serial.println(F("  -> OBSTACLE: stop & turn"));
    stopMotors();
    delay(PAUSE_MS);
    spinRight(SPEED_TURN);
    delay(TURN_MS);
    stopMotors();
    delay(100);
  } else {
    // 트여 있음: 전진
    Serial.println(F("  -> clear: forward"));
    forward(SPEED_CRUISE);
  }

  delay(60);   // 측정 주기
}
