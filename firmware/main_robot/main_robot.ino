/*
 * ============================================================================
 *  책상 위 반려로봇 (Desk Companion Robot) — 메인 펌웨어
 * ----------------------------------------------------------------------------
 *  Arduino Uno · 스키드 스티어(차동구동) · 비차단(non-blocking) 상태머신
 *
 *  상태: IDLE → DRIVE(주행) → AVOID(회피) / CLIFF(낭떠러지) → HOME(귀가) → DOCKED
 *  설계 원칙(README 8번):
 *    - delay() 없이 millis() 기반 타이밍으로 전 상태를 굴린다.
 *    - 낭떠러지 감지는 매 루프 "최우선"으로 검사해 다른 모든 상태를 가로챈다.
 *    - 블루투스 명령은 센서 읽기 사이에서만 처리(SoftwareSerial 지터 회피).
 *
 *  블루투스 명령(단일 문자, HC-05 또는 USB 시리얼):
 *    'F' 주행 시작   'S' 정지   'H' 귀가   'G' 도킹 해제 후 주행   '?' 상태 출력
 * ============================================================================
 */

#include <SoftwareSerial.h>

// ─────────────────────────────────────────────────────────────────────────
//  핀맵 (README 4장 / 00_통합_핀맵.md 와 동일)
// ─────────────────────────────────────────────────────────────────────────
// 모터 — L298N 2개를 좌/우 그룹으로 묶음. EN은 PWM 핀이어야 함.
const uint8_t PIN_L_EN  = 11;  // 좌 EN  (PWM)
const uint8_t PIN_L_IN1 = 10;  // 좌 IN1
const uint8_t PIN_L_IN2 = 9;   // 좌 IN2
const uint8_t PIN_R_EN  = 6;   // 우 EN  (PWM)
const uint8_t PIN_R_IN1 = 5;   // 우 IN1
const uint8_t PIN_R_IN2 = 3;   // 우 IN2

// 블루투스 HC-05 (SoftwareSerial)
const uint8_t PIN_BT_RX = 2;   // 아두이노 RX  ← HC-05 TXD
const uint8_t PIN_BT_TX = 4;   // 아두이노 TX  → HC-05 RXD (1k·2k 전압분배)

// IR 비콘 수신 KY-022 (38kHz 버스트 수신 시 LOW). 방향 유도용.
const uint8_t PIN_IR_L = 7;    // 좌측 수신
const uint8_t PIN_IR_R = 8;    // 우측 수신

// 초음파 HC-SR04 (1개만 사용)
const uint8_t PIN_TRIG = 13;
const uint8_t PIN_ECHO = 12;

// 낭떠러지 FC-51 (비교기 디지털 출력). A0/A1 을 디지털로 사용.
const uint8_t PIN_CLIFF_L = A0;
const uint8_t PIN_CLIFF_R = A1;

// 리드 스위치 (도킹 판정). INPUT_PULLUP, 자석 접촉 시 LOW.
const uint8_t PIN_REED = A2;

// ─────────────────────────────────────────────────────────────────────────
//  튜닝 상수 (개체마다 실측으로 조정)
// ─────────────────────────────────────────────────────────────────────────
// 센서 극성 — 하드웨어에 맞춰 뒤집을 수 있게 상수화
const uint8_t CLIFF_SURFACE_STATE = LOW;  // 바닥이 있을 때 FC-51 출력. 낭떠러지 = 반대값.
const uint8_t REED_DOCKED_STATE   = LOW;  // 자석 접촉(도킹) 시 리드 스위치 값.
const uint8_t IR_ACTIVE_STATE     = LOW;  // 비콘 버스트 수신 시 KY-022 출력.

// 모터 속도 (0~255 PWM)
const uint8_t SPEED_CRUISE = 150;  // 주행
const uint8_t SPEED_TURN   = 170;  // 제자리 회전
const uint8_t SPEED_HOME   = 130;  // 귀가(천천히)

// 회피/낭떠러지 복구 타이밍 (ms)
const uint16_t BACKUP_MS = 350;    // 후진 시간
const uint16_t TURN_MS   = 400;    // 회전 시간

// 초음파
const uint16_t OBSTACLE_CM     = 15;    // 이 거리 이하면 장애물로 판단
const uint16_t ULTRA_PERIOD_MS = 60;    // 초음파 측정 주기
const uint32_t ECHO_TIMEOUT_US = 8000;  // ~1.3m. pulseIn 블로킹 상한을 짧게.

// IR 방향 측정창 (README: 측정창 140ms)
const uint16_t IR_WINDOW_MS = 140;
const uint8_t  IR_MARGIN    = 2;   // 좌우 카운트 차가 이 값 넘어야 방향 확정

// ─────────────────────────────────────────────────────────────────────────
//  전역 상태
// ─────────────────────────────────────────────────────────────────────────
SoftwareSerial bt(PIN_BT_RX, PIN_BT_TX);

enum State { ST_IDLE, ST_DRIVE, ST_AVOID, ST_CLIFF, ST_HOME, ST_DOCKED };
State state = ST_IDLE;
State resumeState = ST_DRIVE;   // AVOID/CLIFF 종료 후 복귀할 상태

// 회피/낭떠러지 시퀀스 진행용
uint8_t  seqPhase = 0;
uint32_t seqStart = 0;
bool     turnRight = true;      // 회전 방향(장애/낭떠러지 반대쪽)

// 초음파
uint32_t lastUltra = 0;
uint16_t lastDistCm = 999;

// IR 방향 카운팅
uint32_t irWindowStart = 0;
uint16_t irCntL = 0, irCntR = 0;      // 현재 창 누적
uint16_t irLatchL = 0, irLatchR = 0;  // 직전 창 확정값
uint8_t  irPrevL = HIGH, irPrevR = HIGH;

// ─────────────────────────────────────────────────────────────────────────
//  모터 제어 (스키드 스티어). speed: -255~255 (음수 = 후진)
// ─────────────────────────────────────────────────────────────────────────
void sideDrive(uint8_t enPin, uint8_t in1, uint8_t in2, int speed) {
  int mag = speed;
  if (mag < 0) mag = -mag;
  if (mag > 255) mag = 255;
  if (speed > 0) { digitalWrite(in1, HIGH); digitalWrite(in2, LOW); }
  else if (speed < 0) { digitalWrite(in1, LOW); digitalWrite(in2, HIGH); }
  else { digitalWrite(in1, LOW); digitalWrite(in2, LOW); }  // 브레이크(코스트)
  analogWrite(enPin, mag);
}

void drive(int left, int right) {
  sideDrive(PIN_L_EN, PIN_L_IN1, PIN_L_IN2, left);
  sideDrive(PIN_R_EN, PIN_R_IN1, PIN_R_IN2, right);
}

void stopMotors()      { drive(0, 0); }
void forward(int s)    { drive(s, s); }
void spinRight(int s)  { drive(s, -s); }   // 좌바퀴 전진 / 우바퀴 후진
void spinLeft(int s)   { drive(-s, s); }

// ─────────────────────────────────────────────────────────────────────────
//  센서
// ─────────────────────────────────────────────────────────────────────────
// 낭떠러지: 좌우 중 하나라도 바닥이 사라지면 true. 함께 어느 쪽인지 기록.
bool cliffDetected(bool &leftCliff, bool &rightCliff) {
  leftCliff  = (digitalRead(PIN_CLIFF_L) != CLIFF_SURFACE_STATE);
  rightCliff = (digitalRead(PIN_CLIFF_R) != CLIFF_SURFACE_STATE);
  return leftCliff || rightCliff;
}

bool isDocked() {
  return digitalRead(PIN_REED) == REED_DOCKED_STATE;
}

// 초음파: 주기적 측정(짧은 pulseIn). 측정 안 한 사이클은 이전 값 유지.
void updateUltrasonic() {
  if (millis() - lastUltra < ULTRA_PERIOD_MS) return;
  lastUltra = millis();
  digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  uint32_t us = pulseIn(PIN_ECHO, HIGH, ECHO_TIMEOUT_US);
  if (us == 0) lastDistCm = 999;              // 타임아웃 = 반사 없음(멀거나 없음)
  else lastDistCm = (uint16_t)(us / 58UL);    // 왕복 → cm
}

bool obstacleAhead() { return lastDistCm <= OBSTACLE_CM; }

// IR 비콘: 매 루프 두 수신기의 falling edge 를 세고, IR_WINDOW 마다 확정.
void updateIrDirection() {
  uint8_t l = digitalRead(PIN_IR_L);
  uint8_t r = digitalRead(PIN_IR_R);
  if (irPrevL != IR_ACTIVE_STATE && l == IR_ACTIVE_STATE) irCntL++;
  if (irPrevR != IR_ACTIVE_STATE && r == IR_ACTIVE_STATE) irCntR++;
  irPrevL = l; irPrevR = r;
  if (millis() - irWindowStart >= IR_WINDOW_MS) {
    irLatchL = irCntL; irLatchR = irCntR;
    irCntL = irCntR = 0;
    irWindowStart = millis();
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  회피 / 낭떠러지 복구 시퀀스 (비차단). 완료 시 true.
//  phase 0: 정지 → 1: 후진 → 2: 회전 → 완료
// ─────────────────────────────────────────────────────────────────────────
bool runRecoverySequence() {
  uint32_t t = millis() - seqStart;
  switch (seqPhase) {
    case 0:  // 즉시 정지
      stopMotors();
      seqPhase = 1; seqStart = millis();
      return false;
    case 1:  // 후진
      forward(-SPEED_CRUISE);
      if (t >= BACKUP_MS) { seqPhase = 2; seqStart = millis(); }
      return false;
    case 2:  // 반대쪽으로 회전
      if (turnRight) spinRight(SPEED_TURN); else spinLeft(SPEED_TURN);
      if (t >= TURN_MS) { stopMotors(); return true; }
      return false;
  }
  return true;
}

void beginRecovery(State back, bool goRight) {
  resumeState = back;
  turnRight = goRight;
  seqPhase = 0; seqStart = millis();
}

// ─────────────────────────────────────────────────────────────────────────
//  명령 처리
// ─────────────────────────────────────────────────────────────────────────
void handleCommand(char c) {
  switch (c) {
    case 'F': case 'f': state = ST_DRIVE;  Serial.println(F("CMD: DRIVE")); break;
    case 'S': case 's': state = ST_IDLE; stopMotors(); Serial.println(F("CMD: STOP")); break;
    case 'H': case 'h':
      state = ST_HOME; irWindowStart = millis(); irCntL = irCntR = 0;
      Serial.println(F("CMD: HOME")); break;
    case 'G': case 'g': state = ST_DRIVE;  Serial.println(F("CMD: UNDOCK->DRIVE")); break;
    case '?': Serial.print(F("STATE=")); Serial.print(state);
              Serial.print(F(" dist=")); Serial.print(lastDistCm);
              Serial.print(F(" irL=")); Serial.print(irLatchL);
              Serial.print(F(" irR=")); Serial.println(irLatchR); break;
    default: break;
  }
}

void readCommands() {
  while (bt.available())     handleCommand(bt.read());
  while (Serial.available()) handleCommand(Serial.read());
}

// ─────────────────────────────────────────────────────────────────────────
//  setup / loop
// ─────────────────────────────────────────────────────────────────────────
void setup() {
  uint8_t outs[] = {PIN_L_EN, PIN_L_IN1, PIN_L_IN2, PIN_R_EN, PIN_R_IN1, PIN_R_IN2, PIN_TRIG};
  for (uint8_t i = 0; i < sizeof(outs); i++) pinMode(outs[i], OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_IR_L, INPUT);
  pinMode(PIN_IR_R, INPUT);
  pinMode(PIN_CLIFF_L, INPUT);
  pinMode(PIN_CLIFF_R, INPUT);
  pinMode(PIN_REED, INPUT_PULLUP);
  stopMotors();

  Serial.begin(9600);
  bt.begin(9600);
  Serial.println(F("Desk Companion Robot ready. Cmds: F/S/H/G/?"));
}

void loop() {
  // 1) 낭떠러지 = 최우선. 다른 어떤 상태든 즉시 가로챈다.
  bool cl = false, cr = false;
  if (cliffDetected(cl, cr) && state != ST_CLIFF && state != ST_DOCKED) {
    // 낭떠러지 반대쪽으로 회전. 좌측 낭떠러지면 오른쪽으로.
    beginRecovery(/*back=*/(state == ST_HOME ? ST_HOME : ST_DRIVE), /*goRight=*/cl);
    state = ST_CLIFF;
  }

  // 2) 센서 갱신 (블로킹 최소화)
  updateUltrasonic();
  updateIrDirection();

  // 3) 명령 처리 (센서 읽기 이후)
  readCommands();

  // 4) 상태 실행
  switch (state) {
    case ST_IDLE:
      stopMotors();
      break;

    case ST_DRIVE:
      if (obstacleAhead()) { beginRecovery(ST_DRIVE, true); state = ST_AVOID; }
      else forward(SPEED_CRUISE);
      break;

    case ST_AVOID:
      if (runRecoverySequence()) state = resumeState;
      break;

    case ST_CLIFF:
      if (runRecoverySequence()) state = resumeState;
      break;

    case ST_HOME: {
      if (isDocked()) { stopMotors(); state = ST_DOCKED; Serial.println(F("DOCKED")); break; }
      if (obstacleAhead()) { beginRecovery(ST_HOME, true); state = ST_AVOID; break; }
      // IR 세기 비교로 조향
      int diff = (int)irLatchL - (int)irLatchR;
      if (diff > IR_MARGIN)       drive(SPEED_HOME / 2, SPEED_HOME);       // 좌가 강함 → 좌로
      else if (-diff > IR_MARGIN) drive(SPEED_HOME, SPEED_HOME / 2);       // 우가 강함 → 우로
      else if (irLatchL + irLatchR == 0) spinRight(SPEED_TURN);            // 신호 없음 → 탐색 회전
      else forward(SPEED_HOME);                                           // 정면 정렬 → 직진
      break;
    }

    case ST_DOCKED:
      stopMotors();  // 'G' 명령으로만 빠져나감
      break;
  }
}
