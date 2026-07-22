/*
 * ============================================================================
 *  책상 위 정서교감 펫 로봇 (Desk Pet Robot)
 *  통합 펌웨어 - 단계적 개발용 골격 (skeleton) 코드
 * ============================================================================
 *
 *  이 코드의 설계 철학
 *  --------------------------------------------------------------------------
 *  지금은 "모터(L298N) 테스트"만 켜져 있습니다.
 *  나머지 센서(초음파/낭떠러지/비콘)는 코드가 이미 다 들어 있지만,
 *  맨 아래 "기능 스위치"에서 꺼져 있어서 컴파일/동작에 영향을 주지 않습니다.
 *
 *  센서를 하나씩 테스트하며 추가할 때:
 *    아래 #define 스위치에서 해당 기능의 0을 1로 바꾸기만 하면 됩니다.
 *    핀 번호는 지금 미리 다 배정해 두었으므로, 나중에 번호를 바꿀 일이 없습니다.
 *    => 이것이 "나중에 연쇄 오류가 안 나게" 만드는 핵심입니다.
 *
 *  단계(Phase) 순서
 *    Phase 1 : 모터만            (지금, USE_MOTOR_TEST = 1)
 *    Phase 2 : + 초음파 장애물    (USE_ULTRASONIC 1)
 *    Phase 3 : + 낭떠러지         (USE_CLIFF 1)
 *    Phase 4 : + 비콘 방향탐지    (USE_BEACON 1)
 *    Phase 5 : 전체 자율주행      (USE_AUTONOMOUS 1)
 * ============================================================================
 */


/* ===========================================================================
 *  [1] 핀 배정 (Pin Map)  ---  지금 전부 예약. 나중에 바꾸지 않음.
 * ===========================================================================
 *  Arduino Uno에서 PWM(속도조절) 가능한 핀: 3, 5, 6, 9, 10, 11
 *  0번,1번 핀은 USB 통신용이라 사용하지 않음.
 *  A4,A5는 나중에 자이로 센서(I2C) 확장 대비해 비워 둠.
 */

// ---- 모터 (L298N) : ENA/ENB는 반드시 PWM 핀이어야 함 ----
const uint8_t PIN_ENA = 5;   // 왼쪽 모터 속도 (PWM)
const uint8_t PIN_IN1 = 7;   // 왼쪽 모터 방향 A
const uint8_t PIN_IN2 = 8;   // 왼쪽 모터 방향 B
const uint8_t PIN_IN3 = 4;   // 오른쪽 모터 방향 A
const uint8_t PIN_IN4 = 2;   // 오른쪽 모터 방향 B
const uint8_t PIN_ENB = 6;   // 오른쪽 모터 속도 (PWM)

// ---- 초음파 (HC-SR04) : Phase 2 ----
const uint8_t PIN_TRIG = 12;
const uint8_t PIN_ECHO = 13;

// ---- 낭떠러지 IR (좌/우, 아래를 향함) : Phase 3 ----
const uint8_t PIN_CLIFF_L = A0;
const uint8_t PIN_CLIFF_R = A1;

// ---- 비콘 IR 수신 (좌/우) : Phase 4 ----
const uint8_t PIN_BEACON_L = A2;
const uint8_t PIN_BEACON_R = A3;

// ---- 부저(선택) : 상태 알림음 ----
const uint8_t PIN_BUZZER = 3;   // PWM 핀 (tone 사용)


/* ===========================================================================
 *  [2] 튜닝 상수 (Tunable Constants)
 * ===========================================================================
 *  실제 부품이 오면 이 숫자들만 조정하면 됩니다. 로직은 건드리지 않습니다.
 */

// 속도 (0~255). 책상 위 저속 주행이 안전하므로 낮게 시작.
const uint8_t SPEED_CRUISE = 130;   // 평상시 전진 속도
const uint8_t SPEED_TURN   = 130;   // 회전 속도
const uint8_t SPEED_STOP   = 0;

// 좌우 모터 힘이 다를 때 직진 보정 (한쪽이 느리면 나중에 조정).
// 100 = 보정 없음. 예: 왼쪽이 약하면 왼쪽을 105로.
const uint8_t TRIM_LEFT  = 100;   // 퍼센트
const uint8_t TRIM_RIGHT = 100;

// 초음파: 이 거리(cm)보다 가까우면 장애물로 판단.
const int OBSTACLE_CM = 12;

// 낭떠러지 IR 판정.
// 대부분의 IR 모듈은 "바닥 감지=LOW, 낭떠러지(반사없음)=HIGH".
// 실제 모듈에 맞게 Phase 3에서 이 값을 뒤집을 수 있게 상수화.
const int CLIFF_DETECTED_LEVEL = HIGH;

// 비콘 방향탐지: 감지율을 세는 시간창(ms)과 판정 임계.
const unsigned long BEACON_WINDOW_MS = 300;  // 0.3초 동안 샘플링
const int BEACON_DIFF_THRESHOLD = 5;         // 좌우 히트수 차이가 이 이상이면 방향 확정

// 동작 시간(ms). 회전·후진 등 짧은 동작의 지속 시간.
const unsigned int MS_BACKUP = 300;
const unsigned int MS_TURN   = 400;


/* ===========================================================================
 *  [3] 기능 스위치 (Feature Flags)  ---  ★ 여기만 켜고 끄면서 단계 진행 ★
 * ===========================================================================
 *  지금은 모터 테스트만 1(켬). 나머지는 0(끔).
 *  센서를 붙여 테스트할 때 해당 줄을 1로 바꾸세요.
 */
#define USE_MOTOR_TEST  1   // Phase 1: 모터 5동작 자동 시연
#define USE_ULTRASONIC  0   // Phase 2: 초음파 거리 측정
#define USE_CLIFF       0   // Phase 3: 낭떠러지 감지
#define USE_BEACON      0   // Phase 4: 비콘 방향탐지
#define USE_AUTONOMOUS  0   // Phase 5: 전체 자율주행 (위 센서들을 종합)

// 안전장치: 자율주행을 켰는데 필요한 센서가 꺼져 있으면 컴파일 단계에서 경고.
#if USE_AUTONOMOUS && (!USE_ULTRASONIC || !USE_CLIFF || !USE_BEACON)
  #warning "USE_AUTONOMOUS는 ULTRASONIC/CLIFF/BEACON이 모두 1이어야 완전하게 동작합니다."
#endif


/* ===========================================================================
 *  [4] 모터 제어 계층 (Motor Layer)
 * ===========================================================================
 *  모든 움직임은 반드시 이 함수들만 통해서 일어납니다.
 *  센서 로직은 나중에 이 함수들을 "호출"만 하면 되므로 서로 얽히지 않습니다.
 */

// 한쪽 모터를 설정: dir = +1 전진, -1 후진, 0 정지 / speed 0~255
void setLeftMotor(int dir, uint8_t speed) {
  uint8_t s = (uint16_t)speed * TRIM_LEFT / 100;
  if (dir > 0)      { digitalWrite(PIN_IN1, HIGH); digitalWrite(PIN_IN2, LOW);  }
  else if (dir < 0) { digitalWrite(PIN_IN1, LOW);  digitalWrite(PIN_IN2, HIGH); }
  else              { digitalWrite(PIN_IN1, LOW);  digitalWrite(PIN_IN2, LOW);  s = 0; }
  analogWrite(PIN_ENA, s);
}

void setRightMotor(int dir, uint8_t speed) {
  uint8_t s = (uint16_t)speed * TRIM_RIGHT / 100;
  if (dir > 0)      { digitalWrite(PIN_IN3, HIGH); digitalWrite(PIN_IN4, LOW);  }
  else if (dir < 0) { digitalWrite(PIN_IN3, LOW);  digitalWrite(PIN_IN4, HIGH); }
  else              { digitalWrite(PIN_IN3, LOW);  digitalWrite(PIN_IN4, LOW);  s = 0; }
  analogWrite(PIN_ENB, s);
}

void moveStop() {
  setLeftMotor(0, 0);
  setRightMotor(0, 0);
}

void moveForward(uint8_t speed) {
  setLeftMotor(+1, speed);
  setRightMotor(+1, speed);
}

void moveBackward(uint8_t speed) {
  setLeftMotor(-1, speed);
  setRightMotor(-1, speed);
}

// 제자리 회전(스키드 조향): 좌우 바퀴를 반대로.
void turnLeftInPlace(uint8_t speed) {
  setLeftMotor(-1, speed);
  setRightMotor(+1, speed);
}

void turnRightInPlace(uint8_t speed) {
  setLeftMotor(+1, speed);
  setRightMotor(-1, speed);
}


/* ===========================================================================
 *  [5] 센서 계층 (Sensor Layer)
 * ===========================================================================
 *  각 센서 읽기 함수. 기능 스위치가 꺼져 있어도 함수 자체는 존재하되
 *  "안전한 기본값"을 돌려주도록 하여, 상위 로직이 항상 컴파일/동작합니다.
 */

// ---- 초음파: 앞쪽 거리(cm). 측정 실패 시 큰 값(=장애물 없음)으로 처리 ----
long readDistanceCm() {
#if USE_ULTRASONIC
  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  // timeout 25ms(약 4m). 신호 없으면 0을 반환하므로 "멀다"로 변환.
  unsigned long dur = pulseIn(PIN_ECHO, HIGH, 25000UL);
  if (dur == 0) return 999;           // 반향 없음 = 앞이 트여 있음
  long cm = (long)(dur * 0.0343 / 2.0);
  return cm;
#else
  return 999;                          // 기능 꺼짐: 항상 "장애물 없음"
#endif
}

bool isObstacleAhead() {
  return readDistanceCm() <= OBSTACLE_CM;
}

// ---- 낭떠러지: 좌/우 각각 반환 ----
bool isCliffLeft() {
#if USE_CLIFF
  return digitalRead(PIN_CLIFF_L) == CLIFF_DETECTED_LEVEL;
#else
  return false;                        // 기능 꺼짐: 항상 "바닥 있음"
#endif
}

bool isCliffRight() {
#if USE_CLIFF
  return digitalRead(PIN_CLIFF_R) == CLIFF_DETECTED_LEVEL;
#else
  return false;
#endif
}

/* ---- 비콘 방향탐지 ------------------------------------------------------
 *  중요한 설계 선택:
 *  IRremote 라이브러리로 신호를 "해독(decode)"하지 않습니다.
 *  CHQ1838 수신모듈은 38kHz 유효신호가 오면 출력을 LOW로 떨어뜨립니다.
 *  따라서 좌/우 핀을 짧은 시간창 동안 digitalRead 하여
 *  "LOW가 몇 번 잡혔는지(히트수)"를 세고, 좌우를 비교합니다.
 *  => 라이브러리를 수신기 2개에 동시에 쓸 때 생기는 충돌을 원천 차단.
 *  반환: -1=왼쪽에 비콘, +1=오른쪽에 비콘, 0=정면/불명확
 */
int readBeaconDirection() {
#if USE_BEACON
  unsigned long t0 = millis();
  unsigned int hitL = 0, hitR = 0;
  while (millis() - t0 < BEACON_WINDOW_MS) {
    if (digitalRead(PIN_BEACON_L) == LOW) hitL++;   // 모듈은 active-low
    if (digitalRead(PIN_BEACON_R) == LOW) hitR++;
  }
  int diff = (int)hitL - (int)hitR;
  if (diff >  BEACON_DIFF_THRESHOLD) return -1;      // 왼쪽이 더 많이 잡음
  if (diff < -BEACON_DIFF_THRESHOLD) return +1;      // 오른쪽이 더 많이 잡음
  if (hitL == 0 && hitR == 0)        return -2;      // 신호 전혀 없음(탐색 필요)
  return 0;                                          // 정면 정렬
#else
  return -2;                                         // 기능 꺼짐: 신호 없음
#endif
}


/* ===========================================================================
 *  [6] 행동 계층 (Behavior Layer)
 * ===========================================================================
 */

// 안전 회전: 어느 쪽이 위험한지에 따라 반대로 회전.
// leftDanger=true면 오른쪽으로 피함.
void avoidByTurning(bool leftDanger) {
  moveStop();
  delay(60);
  moveBackward(SPEED_CRUISE);
  delay(MS_BACKUP);
  moveStop();
  delay(60);
  if (leftDanger) turnRightInPlace(SPEED_TURN);
  else            turnLeftInPlace(SPEED_TURN);
  delay(MS_TURN);
  moveStop();
  delay(60);
}

/* 매 루프에서 가장 먼저 실행되는 안전 점검.
 * 위험을 처리했으면 true를 반환 -> 상위 로직은 이번 루프를 여기서 끝냄.
 * 우선순위: (1) 낭떠러지  (2) 장애물
 */
bool safetyCheck() {
  bool cL = isCliffLeft();
  bool cR = isCliffRight();
  if (cL || cR) {
    // 양쪽 다 낭떠러지면 일단 후진 후 왼쪽으로.
    avoidByTurning(cL && !cR ? true : (cR && !cL ? false : true));
    return true;
  }
  if (isObstacleAhead()) {
    // 장애물은 좌우 정보가 없으므로 기본 왼쪽으로 회피.
    avoidByTurning(true);
    return true;
  }
  return false;
}


/* ===========================================================================
 *  [7] setup()
 * ===========================================================================
 */
void setup() {
  Serial.begin(9600);

  // 모터 핀
  pinMode(PIN_ENA, OUTPUT);
  pinMode(PIN_IN1, OUTPUT);
  pinMode(PIN_IN2, OUTPUT);
  pinMode(PIN_IN3, OUTPUT);
  pinMode(PIN_IN4, OUTPUT);
  pinMode(PIN_ENB, OUTPUT);
  moveStop();                          // 시작 시 반드시 정지 상태 보장

#if USE_ULTRASONIC
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
#endif

#if USE_CLIFF
  pinMode(PIN_CLIFF_L, INPUT);
  pinMode(PIN_CLIFF_R, INPUT);
#endif

#if USE_BEACON
  pinMode(PIN_BEACON_L, INPUT);
  pinMode(PIN_BEACON_R, INPUT);
#endif

  pinMode(PIN_BUZZER, OUTPUT);

  Serial.println(F("=== Desk Pet Robot boot ==="));
#if USE_MOTOR_TEST
  Serial.println(F("Phase 1: MOTOR TEST mode"));
  delay(1500);                         // 손 뗄 시간 (책상에서 들고 있다가 놓기)
#endif
}


/* ===========================================================================
 *  [8] loop()
 * ===========================================================================
 *  기능 스위치에 따라 정확히 하나의 동작 블록만 실행됩니다.
 *  (모터테스트 / 초음파모니터 / ... / 자율주행)
 */
void loop() {

#if USE_MOTOR_TEST
  /* ---- Phase 1: 모터 5동작 자동 시연 ----
   * 전진 → 정지 → 후진 → 정지 → 좌회전 → 정지 → 우회전 → 정지 반복.
   * 시리얼 모니터(9600)에 현재 동작을 출력하여 배선 방향 검증.
   * 바퀴가 반대로 돌면: 해당 모터의 OUT 두 선을 바꿔 끼우거나
   *                     그 모터의 IN 두 핀 번호를 코드에서 맞바꾸면 됨.
   */
  Serial.println(F("FORWARD"));
  moveForward(SPEED_CRUISE);   delay(1200);
  Serial.println(F("STOP"));
  moveStop();                  delay(600);
  Serial.println(F("BACKWARD"));
  moveBackward(SPEED_CRUISE);  delay(1200);
  Serial.println(F("STOP"));
  moveStop();                  delay(600);
  Serial.println(F("TURN LEFT"));
  turnLeftInPlace(SPEED_TURN); delay(800);
  Serial.println(F("STOP"));
  moveStop();                  delay(600);
  Serial.println(F("TURN RIGHT"));
  turnRightInPlace(SPEED_TURN);delay(800);
  Serial.println(F("STOP"));
  moveStop();                  delay(1000);

#elif USE_AUTONOMOUS
  /* ---- Phase 5: 전체 자율주행 ----
   * 1) 안전점검(낭떠러지/장애물) 최우선.
   * 2) 안전하면 비콘 방향으로 이동.
   */
  if (safetyCheck()) {
    // 위험을 처리함. 이번 루프 종료.
  } else {
    int dir = readBeaconDirection();
    if (dir == -2) {
      // 신호 없음: 제자리에서 천천히 돌며 탐색.
      turnRightInPlace(SPEED_TURN);
      delay(150);
      moveStop();
      delay(100);
    } else if (dir == -1) {
      turnLeftInPlace(SPEED_TURN);  delay(120); moveForward(SPEED_CRUISE); delay(150);
    } else if (dir == +1) {
      turnRightInPlace(SPEED_TURN); delay(120); moveForward(SPEED_CRUISE); delay(150);
    } else {
      moveForward(SPEED_CRUISE);    delay(150);
    }
    moveStop();
  }

#else
  /* ---- 센서 단독 테스트 모드 ----
   * 모터테스트/자율주행이 모두 꺼져 있을 때 진입.
   * 켜진 센서의 값을 시리얼 모니터로만 출력(모터는 움직이지 않음).
   * => 센서 하나를 붙이고 값이 제대로 나오는지 안전하게 확인하는 단계.
   */
  #if USE_ULTRASONIC
    Serial.print(F("dist(cm)=")); Serial.println(readDistanceCm());
  #endif
  #if USE_CLIFF
    Serial.print(F("cliffL=")); Serial.print(isCliffLeft());
    Serial.print(F(" cliffR=")); Serial.println(isCliffRight());
  #endif
  #if USE_BEACON
    Serial.print(F("beaconDir=")); Serial.println(readBeaconDirection());
  #endif
  delay(200);
#endif
}
