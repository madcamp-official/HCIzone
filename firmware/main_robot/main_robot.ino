/*
 * ============================================================================
 *  책상 위 반려로봇 (Desk Companion Robot) — 메인 펌웨어
 * ----------------------------------------------------------------------------
 *  Arduino Uno · 스키드 스티어(차동구동) · 비차단(non-blocking) 상태머신
 *
 *  상태: IDLE → DRIVE(주행) → AVOID(회피) / CLIFF(낭떠러지) → HOME(귀가) → ARRIVED
 *  설계 원칙(README 8번):
 *    - delay() 없이 millis() 기반 타이밍으로 전 상태를 굴린다.
 *    - 낭떠러지 감지는 매 루프 "최우선"으로 검사해 다른 모든 상태를 가로챈다.
 *    - 블루투스 명령은 센서 읽기 사이에서만 처리(SoftwareSerial 지터 회피).
 *
 *  블루투스 명령(단일 문자, HC-06 또는 USB 시리얼):
 *    'F' 주행 시작   'S' 정지   'H' 귀가   'G' 재출발   '?' 상태 출력
 * ============================================================================
 */

#include <SoftwareSerial.h>

// ─────────────────────────────────────────────────────────────────────────
//  핀맵 (최종 배치도)
// ─────────────────────────────────────────────────────────────────────────
// 모터 — L298N 2개를 좌/우 그룹으로 묶음. EN은 PWM 핀이어야 함. (고정)
const uint8_t PIN_L_EN  = 11;  // 좌 EN  (PWM)
const uint8_t PIN_L_IN1 = 10;  // 좌 IN1
const uint8_t PIN_L_IN2 = 9;   // 좌 IN2
const uint8_t PIN_R_EN  = 6;   // 우 EN  (PWM)
const uint8_t PIN_R_IN1 = 5;   // 우 IN1
const uint8_t PIN_R_IN2 = 3;   // 우 IN2

// 블루투스 HC-06 (SoftwareSerial)
const uint8_t PIN_BT_RX = 2;   // 아두이노 RX (D2) ← HC-06 TXD
const uint8_t PIN_BT_TX = 4;   // 아두이노 TX (D4) → HC-06 RXD (1k/2k 전압분배)

// IR 비콘 수신 KY-022 (38kHz 버스트 수신 시 LOW). 방향 유도용. 폴링.
const uint8_t PIN_IR_L = 7;    // 좌측 수신
const uint8_t PIN_IR_R = 8;    // 우측 수신

// 초음파 HC-SR04 (1개만 사용). ECHO 직결.
const uint8_t PIN_TRIG = 13;
const uint8_t PIN_ECHO = 12;

// 낭떠러지 KY-032 (IR 근접, 비교기 디지털 출력) 1개. OUT → A0 를 디지털로 사용.
const uint8_t PIN_CLIFF = A0;

// ─────────────────────────────────────────────────────────────────────────
//  튜닝 상수 (개체마다 실측으로 조정)
// ─────────────────────────────────────────────────────────────────────────
// 센서 극성 — 하드웨어에 맞춰 뒤집을 수 있게 상수화
const uint8_t CLIFF_SURFACE_STATE = LOW;  // 바닥이 있을 때 KY-032 출력. 낭떠러지 = 반대값.

// 모터 속도 (0~255 PWM)
const uint8_t SPEED_CRUISE = 150;  // 주행
const uint8_t SPEED_TURN   = 170;  // 제자리 회전
const uint8_t SPEED_HOME   = 130;  // 귀가(천천히)

// 좌/우 채널 속도 보정 (trim). 100 = 보정 없음.
// 직진이 한쪽으로 휘면 빠른 쪽을 낮춘다(예: 왼쪽이 빠르면 TRIM_LEFT=90).
// ※ 좌/우 "면" 단위 보정이다. 같은 쪽 두 바퀴는 PWM을 공유하므로
//   "왼쪽 두 바퀴끼리 다른 속도"는 trim으로 보정되지 않는다(점퍼/모터 편차 문제).
const uint16_t TRIM_LEFT  = 100;
const uint16_t TRIM_RIGHT = 100;

// 회피/낭떠러지 복구 타이밍 (ms)
const uint16_t BACKUP_MS = 350;    // 후진 시간
const uint16_t TURN_MS   = 400;    // 회전 시간

// 초음파
const uint16_t OBSTACLE_CM     = 15;    // 이 거리 이하면 장애물로 판단
const uint16_t ULTRA_PERIOD_MS = 60;    // 초음파 측정 주기
const uint32_t ECHO_TIMEOUT_US = 8000;  // ~1.3m. pulseIn 블로킹 상한을 짧게.

// 비콘 감지 (04_beacon_test 방식): 정지 상태에서 넓은 창으로 LOW 샘플 수를 세어
// 좌/우 세기를 비교한다. main_robot 은 이 측정을 ST_HOME 에서만, 정지 상태로 수행.
const int      IR_SAMPLES    = 2800;  // 약 140ms (50us x 2800) — 비콘 주기(70ms)의 2배
const int      IR_NO_SIGNAL  = 25;    // 좌·우 각각 이 미만이면 신호 없음
const int      IR_CENTER_TOL = 30;    // 좌우 차가 이보다 작으면 정면
// 리드 스위치가 없으므로 도킹은 IR 세기로 근사. 양쪽이 이 값 이상이면 도착. (실측 튜닝)
const int      IR_ARRIVE_STRENGTH = 500;

// 귀가 이동 한 스텝 길이 (ms). 측정→이동을 번갈아 하며 접근.
const uint16_t HOME_FORWARD_MS = 300;  // 정면일 때 전진
const uint16_t HOME_TURN_MS    = 150;  // 방향 보정 회전
const uint16_t HOME_SEARCH_MS  = 200;  // 신호 없을 때 탐색 회전 한 스텝

// 탐색: 제자리 회전 스캔을 이만큼 반복해도 신호가 없으면 새 위치로 이동.
// (엔코더가 없어 실제 각도는 모름 → "회전 스텝 횟수"로 근사. 실측 튜닝.)
const uint8_t  SEARCH_MAX       = 12;  // 대략 한 바퀴 분량(SEARCH_MAX x HOME_SEARCH_MS)
const uint16_t HOME_RELOCATE_MS = 400; // 한 바퀴 훑어도 못 찾으면 전진할 거리

// ─────────────────────────────────────────────────────────────────────────
//  전역 상태
// ─────────────────────────────────────────────────────────────────────────
SoftwareSerial bt(PIN_BT_RX, PIN_BT_TX);

enum State { ST_IDLE, ST_DRIVE, ST_AVOID, ST_CLIFF, ST_HOME, ST_ARRIVED };
State state = ST_IDLE;
State resumeState = ST_DRIVE;   // AVOID/CLIFF 종료 후 복귀할 상태

// 회피/낭떠러지 시퀀스 진행용
uint8_t  seqPhase = 0;
uint32_t seqStart = 0;
bool     turnRight = true;      // 회전 방향

// 초음파
uint32_t lastUltra = 0;
uint16_t lastDistCm = 999;

// 귀가(ST_HOME) 진행용
uint8_t  homePhase = 0;        // 0 = 측정(정지), 1 = 이동(비차단)
uint32_t homeMoveStart = 0;    // 이동 시작 시각
uint16_t homeMoveDur = 0;      // 이번 이동 길이
int      homeLeft = 0, homeRight = 0;  // 마지막 측정 세기(상태 출력용)
uint8_t  searchCount = 0;      // 연속 무신호 스캔 횟수(회전 스텝 수)

// ─────────────────────────────────────────────────────────────────────────
//  로그 출력 — USB(Serial)와 블루투스(bt)로 "동시에" 내보낸다.
//  덕분에 USB 빼고 배터리로 돌려도 컴퓨터가 블루투스로 메시지를 받는다.
// ─────────────────────────────────────────────────────────────────────────
template <typename T> void logPrint(T v)   { Serial.print(v);   bt.print(v); }
template <typename T> void logPrintln(T v) { Serial.println(v); bt.println(v); }

// ─────────────────────────────────────────────────────────────────────────
//  모터 제어 (스키드 스티어). speed: -255~255 (음수 = 후진)
// ─────────────────────────────────────────────────────────────────────────
void sideDrive(uint8_t enPin, uint8_t in1, uint8_t in2, int speed, uint16_t trim) {
  int mag = speed;
  if (mag < 0) mag = -mag;
  mag = (int)(((uint32_t)mag * trim) / 100);   // trim 보정 (방향은 speed 부호로 판단)
  if (mag > 255) mag = 255;
  if (speed > 0) { digitalWrite(in1, HIGH); digitalWrite(in2, LOW); }
  else if (speed < 0) { digitalWrite(in1, LOW); digitalWrite(in2, HIGH); }
  else { digitalWrite(in1, LOW); digitalWrite(in2, LOW); }  // 브레이크(코스트)
  analogWrite(enPin, mag);
}

void drive(int left, int right) {
  sideDrive(PIN_L_EN, PIN_L_IN1, PIN_L_IN2, left,  TRIM_LEFT);
  sideDrive(PIN_R_EN, PIN_R_IN1, PIN_R_IN2, right, TRIM_RIGHT);
}

void stopMotors()      { drive(0, 0); }
void forward(int s)    { drive(s, s); }
void spinRight(int s)  { drive(s, -s); }   // 좌바퀴 전진 / 우바퀴 후진
void spinLeft(int s)   { drive(-s, s); }

// ─────────────────────────────────────────────────────────────────────────
//  센서
// ─────────────────────────────────────────────────────────────────────────
// 낭떠러지: 단일 KY-032. 바닥이 사라지면 true. (센서가 1개라 좌/우 구분 불가)
bool cliffDetected() {
  return digitalRead(PIN_CLIFF) != CLIFF_SURFACE_STATE;
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

// IR 비콘 세기 측정 (04_beacon_test 와 동일). 넓은 창에서 LOW 샘플 수를 센다.
// ~140ms 블로킹이므로 반드시 "정지 상태"에서만 호출한다(ST_HOME 측정 단계).
int signalStrength(uint8_t pin) {
  int lowCount = 0;
  for (int i = 0; i < IR_SAMPLES; i++) {
    if (digitalRead(pin) == LOW) lowCount++;
    delayMicroseconds(50);
  }
  return lowCount;
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
    case 2:  // 회전
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
    case 'F': case 'f': state = ST_DRIVE;  logPrintln(F("CMD: DRIVE")); break;
    case 'S': case 's': state = ST_IDLE; stopMotors(); logPrintln(F("CMD: STOP")); break;
    case 'H': case 'h':
      state = ST_HOME; homePhase = 0; searchCount = 0;
      logPrintln(F("CMD: HOME")); break;
    case 'G': case 'g': state = ST_DRIVE;  logPrintln(F("CMD: GO/DRIVE")); break;
    case '?': logPrint(F("STATE=")); logPrint(state);
              logPrint(F(" dist=")); logPrint(lastDistCm);
              logPrint(F(" irL=")); logPrint(homeLeft);
              logPrint(F(" irR=")); logPrintln(homeRight); break;
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
  pinMode(PIN_CLIFF, INPUT);
  stopMotors();

  Serial.begin(9600);
  bt.begin(9600);
  logPrintln(F("Desk Companion Robot ready. Cmds: F/S/H/G/?"));
}

void loop() {
  // 1) 낭떠러지 = 최우선. 다른 어떤 상태든 즉시 가로챈다.
  if (cliffDetected() && state != ST_CLIFF) {
    // 센서가 1개라 낭떠러지 방향을 알 수 없음 → 후진 후 기본 방향으로 회전.
    beginRecovery(/*back=*/(state == ST_HOME ? ST_HOME : ST_DRIVE), /*goRight=*/true);
    state = ST_CLIFF;
  }

  // 2) 센서 갱신 (블로킹 최소화)
  updateUltrasonic();

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
      if (homePhase == 0) {
        // [측정] 정지 상태에서 좌/우 세기 측정 (모터 노이즈 방지 + 낭떠러지 안전)
        stopMotors();
        homeLeft  = signalStrength(PIN_IR_L);
        homeRight = signalStrength(PIN_IR_R);
        logPrint(F("HOME L=")); logPrint(homeLeft);
        logPrint(F(" R=")); logPrintln(homeRight);

        if (homeLeft < IR_NO_SIGNAL && homeRight < IR_NO_SIGNAL) {
          // 신호 없음: 제자리 회전으로 스캔. SEARCH_MAX 번 돌아도 못 찾으면 새 위치로 이동.
          searchCount++;
          if (searchCount >= SEARCH_MAX) {
            forward(SPEED_HOME); homeMoveDur = HOME_RELOCATE_MS;           // 한 바퀴 훑어도 없음 → 전진
            searchCount = 0;
          } else {
            spinRight(SPEED_TURN); homeMoveDur = HOME_SEARCH_MS;           // 제자리 회전 스캔
          }
        } else if (homeLeft >= IR_ARRIVE_STRENGTH && homeRight >= IR_ARRIVE_STRENGTH) {
          stopMotors(); state = ST_ARRIVED; logPrintln(F("ARRIVED")); break;  // 도착
        } else {
          searchCount = 0;   // 신호 잡음 → 탐색 카운터 리셋
          int diff = homeLeft - homeRight;
          if (abs(diff) < IR_CENTER_TOL) { forward(SPEED_HOME); homeMoveDur = HOME_FORWARD_MS; } // 정면 → 직진
          else if (diff > 0)             { spinLeft(SPEED_TURN);  homeMoveDur = HOME_TURN_MS; }   // 좌 강함 → 좌로
          else                           { spinRight(SPEED_TURN); homeMoveDur = HOME_TURN_MS; }   // 우 강함 → 우로
        }
        homeMoveStart = millis();
        homePhase = 1;
      } else {
        // [이동] 비차단: 낭떠러지·장애물은 루프 상단에서 매 루프 검사됨
        if (obstacleAhead()) { beginRecovery(ST_HOME, true); state = ST_AVOID; homePhase = 0; break; }
        if (millis() - homeMoveStart >= homeMoveDur) { stopMotors(); homePhase = 0; }  // 이동 끝 → 재측정
      }
      break;
    }

    case ST_ARRIVED:
      stopMotors();  // 'G'/'F' 명령으로만 빠져나감
      break;
  }
}
