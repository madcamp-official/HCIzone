# Desksurfer — 데스크톱 펫 & 책상 반려로봇

화면 속 **버추얼 펫**과 책상 위 **물리 로봇**이 하나의 존재처럼 이어지는 프로젝트다.
펫은 투명·항상-위 창에서 다른 앱 창 위를 걸어 다니고, 집(포켓볼)으로 들어가면 그
"영혼"이 물리 로봇으로 넘어간다. 다시 부르면 로봇이 집(IR 비콘)으로 도킹하고, 그
순간 펫이 화면으로 되돌아온다.

```
┌─────────────┐   파일(~/.desktop-pet)   ┌───────────┐   블루투스(HC-06)   ┌──────────────┐
│  펫 (pet.gd) │ ◄──────────────────────► │ bridge.py │ ◄────────────────► │ main_robot.ino│
│  Godot 4.7  │   state / command 파일    │  (Python) │   F/S/H/G/? 명령    │  Arduino Uno  │
└─────────────┘                           └───────────┘                    └──────────────┘
                                                                                   ▲ IR
                                                                          ┌────────┴────────┐
                                                                          │ home_beacon.ino │
                                                                          │ (집 IR 비콘 송신)│
                                                                          └─────────────────┘
```

구성 요소는 세 가지다.

1. **버추얼 펫** (`pet.gd`, `home.gd` + `sprites/`) — Godot 4.7 데스크톱 펫
2. **브리지** (`bridge.py`) — 펫(파일) ↔ 로봇(블루투스 시리얼) 중계
3. **로봇 펌웨어** (`firmware/`) — 로봇 본체(`main_robot.ino`) + 집 비콘(`home_beacon.ino`)

---

## 1. 버추얼 펫 (Godot)

### 실행

**Godot 4.7** 필요.

- Godot 프로젝트 매니저에서 이 폴더를 **Import** 하고 F5, 또는
- 터미널에서: `godot --path .`

메인 씬은 `main.tscn`이며 `pet.gd` 하나가 전체를 구동한다(`project.godot`의
`run/main_scene` = `main.tscn`). 창은 760×720, 테두리 없음·항상 위·픽셀 단위 투명이며,
스프라이트가 차지하는 상자 바깥은 클릭이 밑의 앱으로 통과된다(매 프레임 불투명
영역으로 갱신).

### 조작법

| 입력 | 동작 |
|---|---|
| 좌클릭 드래그 | 펫을 집어 옮긴다(창/아이콘 위에 떨어뜨리면 그 위에 앉음) |
| 좌클릭(드래그 없이) | 쓰다듬기 — 하트가 튀고, 낮잠에서 깨움 |
| 우클릭 | 먹이 주기(사과, 25% 확률로 황금 사과) |
| 가운데 클릭 또는 `P` | 놀이 모드 토글(커서를 쫓아다님) |
| `B` | 캐릭터 순환: Eevee → Snorlax → Fletchling |
| 포켓볼 클릭 또는 `H` | 펫을 볼로 부르기 / 볼에서 꺼내기 |
| 포켓볼 드래그 | 도크 라인을 따라 좌우로 옮김 |
| `Esc` / `Q` | 종료 |

> **키 입력 포커스 주의:** 키(`H`/`P`/`B`/`Esc`)는 **펫 창**이 OS 포커스를 가질 때만
> 동작한다. 포켓볼을 마우스로 클릭하면 포커스가 **포켓볼 창**으로 넘어가므로, 그
> 직후 `H`를 눌러도 반응하지 않는다. 이때는 `Alt+Tab`으로 펫 창에 포커스를 준 뒤
> `H`를 누르면 된다. (포켓볼 클릭은 "리콜 대기"이고, `H`는 로봇 없이 즉시 꺼내는
> 탈출구다 — 아래 [브리지](#2-브리지-bridgepy) 참고.)

### 캐릭터와 행동

기본 캐릭터는 **Fletchling**(`pet.gd`의 `var form: Form = Form.FLETCHLING`). `B`로 순환한다.

- **Eevee / Snorlax** — "고양이" 행동: 걷기 + 중력 포물선 점프로 발판 사이 이동
- **Fletchling** — "새" 행동: 중력 없이 목표 발판으로 부드럽게 활강 비행. 사라진
  발판에서 떨어지거나 공중에서 놓여도 추락 대신 가까운 발판으로 비행. 비행 중 `B`로
  변신도 가능

잠자기·놀이·먹이·귀가는 세 캐릭터가 동일하고, 차이는 발판 사이를 건너는 방식(점프 vs
비행)뿐이다. 그 외 자율 행동:

- **창·아이콘·도크 위를 걷는다.** 중력이 있어 다른 앱 창의 윗변, 보이는 바탕화면
  아이콘, 도크 라인에 착지해 그 위를 오간다. 창이 움직이면 따라 타고, 발판이
  사라지면 (착지 스쿼시와 함께) 떨어진다.
- **놀이 모드**(`P`/가운데 클릭): 커서를 쫓다가 커서가 머리 위면 점프하고, ~35초 뒤
  지쳐 곧 낮잠에 든다.
- **스스로 발판 사이를 점프/비행**하고, 좌우로 배회한다.
- **낮잠**: 깨어난 지 25~60초 뒤 눈을 감고 "Zzz". 12~25초 지속(깨우면 종료).
- **배고픔**: ~45초 굶으면 머리 위에 표시. 먹이면 리셋되고 하트가 뜬다.

### 스프라이트

캐릭터는 `sprites/<Name>/`의 PMD 스타일 시트(`<Anim>-Anim.png` + `AnimData.xml`,
60Hz 틱 단위 프레임)에서 그려진다. 시트는 런타임에 `Image.load_from_file`로 디스크에서
직접 로드해 Godot의 임포트 시스템을 우회하므로 에디터 임포트가 필요 없다.
`sprites/.gdignore`가 에디터의 ~180개 PNG 자동 임포트를 막는다(있어야 함 — 없으면
프로젝트 열 때 "still importing"에 멈출 수 있음).

`SPRITE_SCALE`(7.5×, ≈220px), 상태→시트 매핑은 `pet.gd` 상단 `FORM_DEFS`에 있다.
그림자는 각 시트의 `<Anim>-Shadow.png` 마커에서 만들어 발판 가장자리에 맞춰 클리핑되며
공중에서는 없다. 놀이/낮잠/하트/배고픔 이펙트는 `sprites/move_VFX/`의 PMD VFX다.

### 창 감지 원리

Godot는 다른 앱 창을 못 보므로 외부 헬퍼가 창 사각형을 JSON으로 출력하면 펫이
백그라운드 스레드에서 ~3회/초 폴링한다.

- **Windows:** [helpers/window_list_win.c](helpers/window_list_win.c) (Win32 `EnumWindows`
  + DWM 확장 프레임 경계). MinGW로 빌드:
  ```sh
  gcc -O2 helpers/window_list_win.c -o helpers/window_list.exe
  ```
- **macOS:** [helpers/window_list.c](helpers/window_list.c) (CoreGraphics).
  ```sh
  clang -O2 -framework CoreGraphics -framework CoreFoundation \
    helpers/window_list.c -o helpers/window_list
  ```

헬퍼 바이너리가 없으면 펫은 여전히 실행되지만 도크 라인만 안다. **바탕화면 아이콘**
감지([helpers/desktop_icons.applescript](helpers/desktop_icons.applescript))는
Finder 기반이라 **macOS 전용**이다 — Windows에서는 아이콘을 무시하고 창과 작업표시줄
라인만 발판으로 쓴다.

### 디버그/튜닝 환경변수

`pet.gd`가 읽는 값들:

| 환경변수 | 효과 |
|---|---|
| `PET_DEBUG=1` | 매초 상태/폼/애니메이션/발판 로그 출력 |
| `PET_SPAWN="x,y"` | 지정 좌표(물리 픽셀)에 스폰 |
| `PET_PLAY=1` | 놀이 모드로 시작 |
| `PET_FORM=eevee\|snorlax\|fletchling` | 시작 캐릭터(별칭 `cat`/`parrot`/`bird`) |
| `PET_NAP=1` | 첫 기회에 낮잠 |
| `PET_SNAP=/path.png` (+ `PET_SNAP_AT`) | 실행 후 지정 초에 뷰포트 스냅샷 1장 저장 |
| `PET_NO_ICONS=1` | Finder 아이콘 폴링 생략(macOS에서 권한 프롬프트로 스레드가 멈추는 것 방지) |
| `PET_BRIDGE_DIR` | 브리지 폴더 위치 재지정 |

성격 상수(크기·속도·점프·낮잠 시간 등)는 `pet.gd` 상단에 모여 있다. `SPRITE_SCALE`을
크게 바꾸면 `project.godot`의 창 크기도 맞춰야 한다.

---

## 2. 집(포켓볼)과 가상↔실물 브리지

도크 라인 위에 클래식 빨강 포켓볼([home.gd](home.gd))이 자기 창으로 떠 있다. 클릭하거나
`H`를 누르면 펫이 걸어/날아 가서 볼이 열리고 빛과 함께 빨려 들어간 뒤 닫힌다. 안에
있는 동안 버튼이 빨간 LED처럼 깜빡이고 가끔 흔들리며 반짝임이 샌다. 몇 분마다 스스로도
집에 들어간다.

집에 들어가는 순간이 **물리 로봇으로의 인계 지점**이다. 로봇 브리지가 필요한 모든
것은 `~/.desktop-pet/`(Windows: `%USERPROFILE%\.desktop-pet`, `PET_BRIDGE_DIR`로 재지정)에 있다.

| 파일 | 방향 | 의미 |
|---|---|---|
| `state` | 펫 → 로봇 | `virtual`(화면에 있음) / `home`(볼 안, 로봇이 자유 주행) / `recall`(사용자가 다시 부름 → 로봇은 도킹) |
| `command` | 로봇 → 펫 | `enter_home` / `exit_home` / `feed` / `play` 중 하나. 펫이 ~0.3초 내 읽고 삭제 |
| `on_enter_home` | 펫 → 로봇 | 펫이 집에 들어간 순간 실행되는 훅(로봇 깨우기) |
| `on_exit_home` | 펫 → 로봇 | 펫이 나온 순간 실행되는 훅(로봇 재우기) |

**리콜(소환) 왕복:** 볼을 클릭하면 펫이 즉시 튀어나오지 않는다 — 영혼이 로봇에 있으므로
`state`를 `recall`로 바꾸고 볼이 계속 흔들리며 기다린다. 브리지가 이를 로봇의 `H`(도킹
귀가)로 바꾸고, 로봇이 도착(`ARRIVED`)하면 `command`에 `exit_home`을 써서 펫을 꺼낸다.
로봇/브리지 없이 실행 중이라면 볼 클릭만으로는 갇히므로, **`H` 키가 로봇 없이 즉시
꺼내는 탈출구**다.

### bridge.py

PC에서 상시 돌며 HC-06 블루투스로 로봇과, 파일로 펫과 연결한다.

```sh
pip install pyserial
python bridge.py       # 키 입력은 이 콘솔에 포커스를 두고
```

블루투스 시리얼 포트를 자동 탐지한다(원하면 `BRIDGE_PORT` 환경변수로 강제 지정).

**프로토콜** (로봇에 보내는 단일 문자): `F`=주행 `S`=정지 `H`=귀가 `G`=재출발 `?`=상태요청.
로봇은 `ARRIVED`(도착 1회)와 `STATE=n dist=.. irL=.. irR=..`(`?` 응답)를 보낸다.

**상태 동기화** (펫 `state` → 로봇 명령): `virtual`→`S`, `home`→`F`, `recall`→`H`,
그리고 로봇 `ARRIVED`/`STATE=5`→ 펫 `exit_home`.

**신뢰성 설계(A-1~A-5):** 도착 감지 이중화(단발 ARRIVED + 주기적 `?` 폴링), 재연결 시
진행 중 귀가 보존, 연결 핸드셰이크로 잘못된 COM 포트 배제, 펫이 나올 때/브리지 종료 시
`S`로 무인 주행 방지, `recall` 중 `H` 유실 시 폴링마다 재전송.

**수동 비콘 우회(B-1):** IR 비콘 도킹이 아직 불안정해 `ARRIVED`가 안 올 때를 위한
수동 오버라이드. 콘솔에서:

| 키 | 로봇 | 펫 |
|---|---|---|
| `s` | 정지(`S`) | 볼 안(`home`/`recall`)이면 즉시 꺼냄(`exit_home`) |
| `f` | 주행(`F`) | 집으로 보냄(`enter_home`) |
| `h` | 귀가(`H`, 비콘 유도) | 영향 없음 — 실제 도킹 판정은 로봇의 `ARRIVED`에만 맡김 |
| `?` / `q`·`Esc` | 상태 / 종료 | — |

`s`의 펫-꺼내기는 자동 도착 감지(A-1)와 **똑같은 판정 함수**(`trigger_exit_if_home`)를
공유하므로 두 경로가 어긋나지 않는다. 비콘이 정상 동작해도 이 수동 경로는 그대로
병행 가능하다.

### LED 예제(선택)

[helpers/arduino/led_bridge/led_bridge.ino](helpers/arduino/led_bridge/led_bridge.ino)는
시리얼로 `ON`/`OFF`를 받아 LED(기본 온보드 LED, 배선 불필요)를 켜는 최소 스케치이고,
[helpers/arduino_led.sh](helpers/arduino_led.sh)가 그 셸 쪽이다(**macOS 전용** —
`stty -f` 사용). `on_enter_home`/`on_exit_home` 훅에서 이 스크립트를 호출하도록 예시가
꾸며져 있으니, 실제 로봇의 깨우기/재우기 명령으로 이 두 줄만 바꾸면 된다.

---

## 3. 로봇 펌웨어 (`firmware/`)

Arduino Uno 기반. 전체 배선은 [firmware/00_통합_핀맵.md](firmware/00_통합_핀맵.md)에
정리되어 있다(우노 20 I/O 중 12핀 사용).

### main_robot.ino — 로봇 본체

[firmware/main_robot/main_robot.ino](firmware/main_robot/main_robot.ino).
스키드 스티어(차동구동), `delay()` 없는 `millis()` 기반 비차단 상태머신.

**상태:** `IDLE → DRIVE(주행) → AVOID(회피) / CLIFF(낭떠러지) → HOME(귀가) → ARRIVED`

**명령**(HC-06 블루투스 또는 USB 시리얼, 단일 문자): `F`=주행 `S`=정지 `H`=귀가
`G`=재출발 `?`=상태 출력.

**설계 원칙:**

- 매 루프 **명령을 가장 먼저** 처리해 `S`(정지)가 항상 즉시 반영된다.
- 이어서 **낭떠러지 안전검사**가 움직이는 모든 상태를 가로채 후진·회전으로 복구한다.
  단 이미 멈춘 `IDLE`/`ARRIVED`는 존중하고, 같은 낭떠러지를 연속 `CLIFF_STREAK_MAX`(3)회
  넘게 만나면 후방 센서가 없으므로 더 후진하지 않고 그 자리에 정지·유지한다.
- 정지는 관성(coast)이 아니라 **능동 제동**(모터 단락)으로 확실히 세운다.
- 초음파 장애물은 단발 반사 오탐을 막기 위해 연속 `OBSTACLE_CONFIRM`(2)회 근접해야 확정.
- **귀가(HOME):** 정지 상태에서 좌/우 IR 세기를 측정(모터 노이즈·낭떠러지 안전)하고,
  신호가 없으면 제자리 회전으로 스캔(한 바퀴 훑어도 없으면 전진해 새 위치로), 신호가
  있으면 좌우 세기 차로 직진/좌·우회전해 접근. 양쪽 세기가 `IR_ARRIVE_STRENGTH`(500)
  이상이면 `ARRIVED`로 전환하고 `"ARRIVED"`를 출력한다(브리지가 이를 받아 펫을 꺼냄).
  리드 스위치가 없어 도킹은 IR 세기로 근사한다.

주요 핀: 모터 좌 `EN=11/IN1=10/IN2=9`, 우 `EN=6/IN1=5/IN2=3`(EN은 PWM); HC-06
`RX=2/TX=4`(TX는 1k/2k 전압분배); IR 수신 `L=7/R=8`(KY-022, 38kHz 버스트 시 LOW);
초음파 `TRIG=13/ECHO=12`(HC-SR04); 낭떠러지 `A0`(KY-032). 모터는 별도 배터리(7–12V)로
L298N에 공급하고 모든 GND는 공통이다.

### home_beacon.ino — 집 IR 비콘 송신기

[firmware/home_beacon/home_beacon.ino](firmware/home_beacon/home_beacon.ino).
**별도 아두이노 보드**에 올리는 38kHz IR 비콘. 로봇이 이 신호를 향해 도킹한다.

시리얼(9600bps) 명령: `H`=비콘 켜기 `S`=끄기 `?`=상태. 전원 인가 시 기본 꺼짐 —
`H`를 입력해야 송출을 시작한다.

**타이밍(절대 임의 변경 금지):** "600µs 송신 + 600µs 휴식"을 8번 반복(패킷 ≈9.6ms) 후
60ms 휴식 → 총 주기 ≈70ms. 로봇의 수신 창(≈140ms = 이 주기의 2배)에 정밀하게 맞춰져
있다. 반송파를 끊김 없이 길게(>10ms) 내보내면 수신칩(VS1838B/KY-022)의 AGC가 이를
배경 신호로 보고 이득을 낮춰 출력을 눌러버려 인식이 실패하므로, 펄스로 끊어 보내는
것이 핵심이다.

배선: IR LED 애노드(+) → `D3`, 캐소드(-) → `GND`(KY-005 모듈이면 S핀=D3, -핀=GND).
현재는 저항 없이 직결이라, 100Ω~1kΩ 직렬 저항을 넣으면 핀 열화 위험이 사실상
사라진다(밝기/사거리 영향 거의 없음). 적외선은 눈에 안 보이므로, 온보드 LED(D13)가
패킷마다 짧게 깜빡이면 정상 송출 중이라는 뜻이다.

### 브링업/디버그 테스트 스케치 (`firmware/tests/`)

| 스케치 | 용도 |
|---|---|
| `01_motor_test` | 모터/L298N |
| `02_ultrasonic_test` | HC-SR04 초음파 |
| `03_cliff_test` | KY-032 낭떠러지 |
| `04_beacon_test` | KY-022 IR 비콘 수신 세기 |
| `05_bluetooth_test` | HC-06 블루투스 |
| `06_obstacle_avoid_test` | 장애물 회피 |
| `07_cliff_avoid_test` | 낭떠러지 회피 |
| `08_homing_test` | 비콘 귀가 |
| `09_ir_rx_debug` | IR 수신 원시 신호(LOW 비율) 진단 — 송/수신 문제 구분 |
| `10_ir_tx_selftest` | IR 송신 단독 점검(1초 ON/OFF, 휴대폰 카메라 확인용) |

---

## 레거시 파일 / 알려진 제약

- `main.gd`, `parrot.gd`, `fly.gd`는 옛 앵무새 단독 데모의 잔재로, `project.godot`의
  메인 씬(`main.tscn` → `pet.gd`)에 연결되어 있지 않아 **동작에 영향이 없다**(정리 시
  삭제 가능).
- 키 입력은 펫 창 포커스가 필요하다(위 조작법의 포커스 주의 참고). `Esc`/`Q` 종료도
  마찬가지.
- 멀티 모니터에서는 집이 펫이 있는 화면으로 따라온다.
- Windows에서 브리지 훅(`on_enter_home`/`on_exit_home`)은 셸 스크립트가 아니라
  실행 가능한 `.exe`/`.bat`이어야 한다.
- 집 위치는 재시작 시 저장되지 않는다.
- IR 비콘 도킹이 하드웨어적으로 불안정한 동안에는 `bridge.py`의 **수동 우회(B-1,
  콘솔 `s`/`f`)**로 펫의 등장/귀가를 직접 맞출 수 있다.
