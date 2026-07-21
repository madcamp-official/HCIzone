/*
 * 01_motor_test — 모터 주행 검증 (스키드 스티어, 2채널)
 * ---------------------------------------------------------------------------
 * L298N 2개를 좌/우 채널로 묶어(각 드라이버 두 채널을 점퍼로 묶음) 3핀씩 제어.
 * 전진 → 후진 → 좌회전 → 우회전 반복.
 *
 * 핀맵 (통합 배치도):
 *   좌 채널: EN=11(PWM) IN1=10 IN2=9
 *   우 채널: EN=6(PWM)  IN1=5  IN2=3
 *
 * 한쪽이 거꾸로 돌면 INVERT_LEFT/RIGHT 를 true 로, 좌우가 바뀌었으면
 * 좌/우 핀 정의를 서로 바꿔주세요. 직진이 휘면 TRIM_* 로 미세 보정.
 */

// ---- 좌 채널 ----
const uint8_t L_EN = 11, L_IN1 = 10, L_IN2 = 9;
// ---- 우 채널 ----
const uint8_t R_EN = 6,  R_IN1 = 5,  R_IN2 = 3;

const uint8_t SPEED_CRUISE = 150;
const uint8_t SPEED_TURN   = 180;
const uint16_t MS_TURN_90  = 500;   // 실측 보정

const bool INVERT_LEFT  = false;
const bool INVERT_RIGHT = false;
const uint16_t TRIM_LEFT  = 100;    // 100 = 보정 없음
const uint16_t TRIM_RIGHT = 100;

// side: 0=좌 1=우 / dir: +1 전진 -1 후진 0 정지
void sideDrive(uint8_t en, uint8_t in1, uint8_t in2, int dir, uint8_t speed,
               bool invert, uint16_t trim) {
  if (invert) dir = -dir;
  uint16_t s = ((uint16_t)speed * trim) / 100;
  if (s > 255) s = 255;
  if (dir > 0)      { digitalWrite(in1, HIGH); digitalWrite(in2, LOW); }
  else if (dir < 0) { digitalWrite(in1, LOW);  digitalWrite(in2, HIGH); }
  else              { digitalWrite(in1, LOW);  digitalWrite(in2, LOW); s = 0; }
  analogWrite(en, (uint8_t)s);
}

void left(int dir, uint8_t sp)  { sideDrive(L_EN, L_IN1, L_IN2, dir, sp, INVERT_LEFT,  TRIM_LEFT); }
void right(int dir, uint8_t sp) { sideDrive(R_EN, R_IN1, R_IN2, dir, sp, INVERT_RIGHT, TRIM_RIGHT); }

void moveStop()              { left(0,0); right(0,0); }
void moveForward(uint8_t s)  { left(+1,s); right(+1,s); }
void moveBackward(uint8_t s) { left(-1,s); right(-1,s); }
void turnLeftInPlace(uint8_t s)  { left(-1,s); right(+1,s); }
void turnRightInPlace(uint8_t s) { left(+1,s); right(-1,s); }

void setup() {
  uint8_t outs[] = {L_EN, L_IN1, L_IN2, R_EN, R_IN1, R_IN2};
  for (uint8_t i = 0; i < sizeof(outs); i++) pinMode(outs[i], OUTPUT);
  moveStop();
  Serial.begin(9600);
  Serial.println(F("=== motor test (skid steer) ==="));
  delay(2000);
}

void loop() {
  Serial.println(F("FORWARD"));    moveForward(SPEED_CRUISE);  delay(1200);
  Serial.println(F("STOP"));       moveStop();                 delay(600);
  Serial.println(F("BACKWARD"));   moveBackward(SPEED_CRUISE); delay(1200);
  Serial.println(F("STOP"));       moveStop();                 delay(600);
  Serial.println(F("TURN LEFT"));  turnLeftInPlace(SPEED_TURN);  delay(MS_TURN_90); moveStop(); delay(600);
  Serial.println(F("TURN RIGHT")); turnRightInPlace(SPEED_TURN); delay(MS_TURN_90); moveStop(); delay(1200);
}
