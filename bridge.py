#!/usr/bin/env python3
"""
DeskSurfer 브리지 — 로봇(블루투스 시리얼) ↔ 버츄얼 펫(파일) 중계.

이 프로그램은 PC에서 상시 돌아가며, HC-06 블루투스로 연결된 책상 로봇과
Godot 펫 앱을 이어준다. 둘은 서로를 직접 모르고, 오직 이 브리지를 통해서만
하나의 존재처럼 이어진다.

━━ 프로토콜 (firmware main_robot.ino 기준) ━━
  · 로봇에 보내는 명령(단일 문자): F=주행 S=정지 H=귀가 G=재출발 ?=상태요청
  · 로봇이 보내는 것(줄 단위, USB+BT 동시):
      "ARRIVED"                       도착 순간 1회
      "STATE=n dist=.. irL=.. irR=.." '?' 응답. n = 0..5 (아래 ROBOT_* 참고)

━━ 상태 동기화 (펫 state 파일 → 로봇 명령) ━━
  · virtual : 영혼이 화면에 있음 → 로봇 'S'(정지)
  · home    : 영혼이 로봇으로 넘어감(볼에 들어감) → 로봇 'F'(자유 주행)
  · recall  : 사용자가 볼을 눌러 펫을 다시 부름 → 로봇 'H'(도킹 귀가). 로봇이
              ARRIVED 하면 exit_home 으로 펫을 꺼내 왕복을 닫는다. 그동안 볼은
              계속 진동하며 기다린다.

━━ 신뢰성 설계 (A-1 ~ A-5) ━━
  A-1 도착 감지 이중화 : 단발 "ARRIVED"에만 의존하지 않고, 주기적으로 '?'를
      보내 STATE=5(ARRIVED)를 폴링한다. 도착이면 exit_home 을 멱등하게 쓴다
      (펫은 HOME 상태가 아니면 exit_home 을 무시하므로 반복 전송이 안전).
      → "ARRIVED 한 줄 유실 시 펫이 볼에 영영 갇힘" 문제 해소.
  A-2 로봇 상태 추적   : STATE 폴링으로 로봇 FSM을 알기에, 재연결 시 로봇이 이미
      귀가(HOME)/도착(ARRIVED) 중이면 'F'를 보내지 않는다. → 진행 중 귀가를 깨지 않음.
  A-3 연결 핸드셰이크   : 포트를 연 뒤 '?'를 보내 STATE= 응답이 오는 포트만 채택.
      HC-06의 잘못된(수신) COM 오선택을 걸러낸다.
  A-4 desync 방지 정지 : 펫이 볼에서 나올 때(state=virtual)와 브리지 종료 시
      로봇에 'S'를 보내 무인 주행을 막는다.
  A-5 귀가 명령 보정   : state=recall 인데 로봇이 아직 HOME/ARRIVED 가 아니면
      폴링마다 'H'를 조용히 재전송한다. → 'H' 한 번 유실돼도 결국 도킹한다.

포트 번호가 매번 바뀌는 문제 → 하드코딩하지 않고 블루투스 시리얼 포트를
자동 탐지한다(발신/Outgoing COM). 원하면 BRIDGE_PORT 환경변수로 강제 지정한다.

실행 전:  pip install pyserial
실행:     python bridge.py       (키 입력을 받으려면 이 콘솔 창에 포커스를 둔다)
"""

import os
import re
import time
from pathlib import Path

import serial
from serial.tools import list_ports

# 키보드 논블로킹 입력(Windows 전용). 다른 OS면 수동 트리거만 비활성화된다.
try:
    import msvcrt
    HAVE_KB = True
except ImportError:
    msvcrt = None
    HAVE_KB = False


# 로봇 펌웨어(main_robot.ino)의 Serial/HC-06 속도와 반드시 일치해야 한다.
BAUD = 9600

# 로봇 FSM 상태값 (main_robot.ino enum State 와 1:1). '?' 응답의 STATE=n.
ROBOT_IDLE, ROBOT_DRIVE, ROBOT_AVOID, ROBOT_CLIFF, ROBOT_HOME, ROBOT_ARRIVED = range(6)
ROBOT_NAMES = {0: "IDLE", 1: "DRIVE", 2: "AVOID", 3: "CLIFF", 4: "HOME", 5: "ARRIVED"}

PET_STATE_POLL_SEC = 0.2   # 펫의 state 파일을 읽는 주기
ROBOT_POLL_SEC     = 1.0   # 로봇에 '?'를 보내 STATE를 확인하는 주기
HANDSHAKE_SEC      = 2.0    # 연결 후 STATE 응답을 기다리는 시간

STATE_RE = re.compile(r"STATE=(\d+)")


# ---------------------------------------------------------------------------
#  브리지 폴더 (펫과 공유하는 "우편함")
# ---------------------------------------------------------------------------
def find_bridge_dir() -> Path:
    """펫(pet.gd)이 쓰는 것과 똑같은 폴더를 찾는다.

    기본값은 ~/.desktop-pet (Windows: %USERPROFILE%\\.desktop-pet).
    펫과 브리지 둘 다 PET_BRIDGE_DIR 환경변수로 같은 폴더를 가리키게 할 수도 있다.
    """
    d = os.environ.get("PET_BRIDGE_DIR", "").strip()
    if not d:
        home = os.environ.get("USERPROFILE") or os.environ.get("HOME") or "."
        d = os.path.join(home, ".desktop-pet")
    p = Path(d)
    p.mkdir(parents=True, exist_ok=True)
    return p


def send_to_pet(bridge_dir: Path, cmd: str) -> None:
    """펫에게 명령을 보낸다 = command 파일에 써넣는다.

    펫은 command 파일을 0.3초마다 읽고 곧바로 삭제하므로, 그냥 덮어쓰면 된다.
    받을 수 있는 명령: enter_home / exit_home / feed / play
    """
    (bridge_dir / "command").write_text(cmd + "\n", encoding="utf-8")
    print(f"  [펫 ←] command = {cmd}")


def read_state(bridge_dir: Path):
    """펫이 쓴 state 파일을 읽는다. "virtual" 또는 "home".

    반환: 정리된 문자열, 파일 없으면 "", 읽기 실패(펫이 쓰는 중 등)면 None.
    """
    path = bridge_dir / "state"
    try:
        if not path.exists():
            return ""
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def parse_robot_state(line: str):
    """로봇이 보낸 줄에서 STATE=n 을 뽑는다. 없으면 None."""
    m = STATE_RE.search(line)
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------------------
#  블루투스 시리얼 포트 자동 탐지 + 핸드셰이크 (A-3)
# ---------------------------------------------------------------------------
def candidate_ports() -> list:
    """열어볼 후보 COM 포트 목록. BRIDGE_PORT가 있으면 그것만 쓴다."""
    forced = os.environ.get("BRIDGE_PORT", "").strip()
    if forced:
        return [forced]
    bt = []
    for p in list_ports.comports():
        blob = f"{p.description} {p.manufacturer or ''} {p.hwid or ''}".lower()
        if "bluetooth" in blob:
            bt.append(p.device)
    return sorted(bt)


def handshake(ser: serial.Serial, timeout: float = HANDSHAKE_SEC):
    """'?'를 보내고 STATE=n 응답을 기다린다. 성공 시 로봇 상태(int), 실패 시 None.

    이 응답이 오는 포트만 "진짜 로봇"으로 인정한다(HC-06 수신 COM 오선택 방지, A-3).
    """
    try:
        ser.write(b"?")
        ser.flush()
    except Exception:
        return None
    deadline = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < deadline:
        try:
            data = ser.read(64)
        except Exception:
            return None
        if data:
            buf += data
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                st = parse_robot_state(raw.decode("utf-8", "replace"))
                if st is not None:
                    return st
    return None


def connect():
    """후보 포트를 하나씩 열고 '?' 핸드셰이크가 통하는 것을 채택한다.

    반환: (ser, robot_state) 성공, (None, None) 실패.
    """
    ports = candidate_ports()
    if not ports:
        print("[대기] 블루투스 시리얼 포트를 못 찾음. "
              "(HC-06 페어링 확인 / BRIDGE_PORT 로 지정 가능)")
        return None, None
    for cand in ports:
        try:
            ser = serial.Serial(cand, BAUD, timeout=0.2)
        except Exception as e:
            print(f"  {cand} 열기 실패: {e}")
            continue
        time.sleep(0.3)             # HC-06 연결 직후 안정화
        # 부팅 잡음만 비운다. 여기서 혹시 대기 중이던 ARRIVED를 지우더라도
        # 이후 STATE 폴링(A-1)이 도착을 다시 잡아내므로 안전하다.
        try:
            ser.reset_input_buffer()
        except Exception:
            pass
        st = handshake(ser)         # A-3: 응답 오는 포트만 인정
        if st is not None:
            print(f"[연결] {cand} @ {BAUD}bps (로봇 STATE={st} {ROBOT_NAMES.get(st, '?')})")
            return ser, st
        print(f"  {cand}: STATE 응답 없음(로봇 아님?) → 다음 후보")
        try:
            ser.close()
        except Exception:
            pass
    return None, None


def send_to_robot(ser: serial.Serial, ch: str, why: str = "", quiet: bool = False) -> None:
    """로봇에 단일 문자 명령을 보낸다. F=주행 S=정지 H=귀가 G=재출발 ?=상태."""
    try:
        ser.write(ch.encode("ascii"))
        ser.flush()
        if not quiet:
            note = f" ({why})" if why else ""
            print(f"  [로봇 ←] '{ch}'{note}")
    except Exception as e:
        if not quiet:
            print(f"  [로봇 ←] '{ch}' 전송 실패: {e}")


# ---------------------------------------------------------------------------
#  수동 트리거 (키보드)
# ---------------------------------------------------------------------------
def key_action(ch: str):
    """키 한 글자 → (로봇에 보낼 명령 or None, 종료요청 bool). 순수 함수."""
    low = ch.lower()
    if low == "h":
        return ("H", False)     # 귀가 (비콘 유도)
    if low == "f":
        return ("F", False)     # 주행
    if low == "s":
        return ("S", False)     # 정지
    if ch == "?":
        return ("?", False)     # 상태 요청
    if low == "q" or ch == "\x1b":
        return (None, True)     # 종료 (q 또는 Esc)
    return (None, False)


def poll_keyboard(ser: serial.Serial) -> bool:
    """콘솔 키 입력을 논블로킹으로 처리한다. 종료 요청 시 True.

    이 콘솔 창에 포커스가 있을 때만 키가 잡힌다(수동 트리거의 특성).
    """
    if not HAVE_KB:
        return False
    quit_requested = False
    while msvcrt.kbhit():
        ch = msvcrt.getwch()
        if ch in ("\x00", "\xe0"):        # 화살표 등 특수키 접두 → 다음 바이트 버림
            if msvcrt.kbhit():
                msvcrt.getwch()
            continue
        cmd, want_quit = key_action(ch)
        if cmd is not None:
            reasons = {"H": "수동: 귀가", "F": "수동: 주행",
                       "S": "수동: 정지", "?": "수동: 상태 요청"}
            send_to_robot(ser, cmd, reasons.get(cmd, "수동"))
        if want_quit:
            quit_requested = True
    return quit_requested


# ---------------------------------------------------------------------------
#  메인 루프
# ---------------------------------------------------------------------------
def main() -> None:
    bridge_dir = find_bridge_dir()
    print(f"[브리지] 우편함 = {bridge_dir}")
    print("[브리지] 방향 A: 로봇 도착(ARRIVED/STATE=5) → 펫 exit_home  (폴링 이중화)")
    print("[브리지] 방향 B: 펫 home→'F' / recall→'H'(도킹) / virtual→'S'")
    if HAVE_KB:
        print("[키] h=귀가  f=주행  s=정지  ?=상태  q/Esc=종료  "
              "(이 창에 포커스를 두고 눌러라)")
    else:
        print("[키] 이 OS에선 키보드 트리거 비활성 (Ctrl+C 로 종료)")

    # 시작 시점의 펫 state를 기준값으로 삼는다(시작만으로는 명령을 쏘지 않음).
    last_state = read_state(bridge_dir) or ""

    ser = None
    robot_state = None            # 로봇 FSM (STATE 폴링으로 갱신). 미상이면 None
    printed_state = None          # STATE 로그 스팸 억제용(변할 때만 출력)
    buf = b""
    next_pet_poll = 0.0
    next_robot_poll = 0.0

    def trigger_exit_if_home():
        """로봇이 도착했고 펫이 아직 볼 안이면 꺼낸다 (멱등, A-1).

        볼 안 상태는 "home"(로봇 자유 주행)과 "recall"(소환해 도킹 대기) 둘 다다.
        소환 중(recall)일 때도 반드시 꺼내야 왕복이 닫힌다 — 여길 "home"으로만
        좁히면 소환 후 도착해도 펫이 볼에 영영 갇힌다.
        """
        if read_state(bridge_dir) in ("home", "recall"):
            send_to_pet(bridge_dir, "exit_home")

    try:
        while True:
            # 포트가 없으면 연결(재연결)을 시도한다.
            if ser is None:
                ser, robot_state = connect()
                if ser is None:
                    time.sleep(3)   # 연결 대기 (이 구간의 종료는 Ctrl+C)
                    continue
                printed_state = robot_state
                buf = b""
                # A-2: 재연결 시점에 펫이 이미 볼 안(home)이고, 로봇이 귀가/도착
                # 중이 아니라면(=아직 못 깨어난 상태) 주행을 시작시킨다.
                cur = read_state(bridge_dir)
                if cur is not None:
                    last_state = cur
                    if cur == "home" and robot_state not in (ROBOT_HOME, ROBOT_ARRIVED):
                        send_to_robot(ser, "F", "재연결: 펫이 집 안 & 로봇 미귀가 → 주행")
                    elif cur == "recall" and robot_state not in (ROBOT_HOME, ROBOT_ARRIVED):
                        send_to_robot(ser, "H", "재연결: 펫 소환 중 & 로봇 미귀가 → 귀가")

            # --- 로봇이 보낸 줄 읽기 ---
            try:
                data = ser.read(256)
            except Exception as e:
                print(f"[끊김] 시리얼 오류: {e}. 재연결 시도...")
                try:
                    ser.close()
                except Exception:
                    pass
                ser = None
                time.sleep(1)
                continue

            if data:
                buf += data
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    text = raw.decode("utf-8", "replace").strip()
                    if not text:
                        continue
                    st = parse_robot_state(text)
                    if st is not None:
                        # STATE 응답: 상태가 바뀔 때만 출력(1초 폴링 스팸 억제).
                        robot_state = st
                        if st != printed_state:
                            print(f"[로봇 STATE] {ROBOT_NAMES.get(st, st)}")
                            printed_state = st
                    else:
                        print(f"[로봇 →] {text}")
                    # A-1: 도착 감지 — 단발 ARRIVED 든 STATE=5 든 모두 반응(멱등).
                    if "ARRIVED" in text.upper() or st == ROBOT_ARRIVED:
                        trigger_exit_if_home()

            now = time.monotonic()

            # A-1: 주기적으로 '?'를 보내 STATE를 폴링(조용히). 응답은 위 읽기 루프에서 처리.
            if now >= next_robot_poll:
                next_robot_poll = now + ROBOT_POLL_SEC
                send_to_robot(ser, "?", quiet=True)
                # A-5: 펫이 소환(recall) 중인데 로봇이 아직 귀가(HOME)/도착(ARRIVED)이
                # 아니면 'H'가 유실된 것 → 폴링마다 조용히 재전송(멱등). 볼은 계속
                # 진동하며 기다리므로, 이 재전송이 "영영 안 오는" desync 를 막는다.
                if last_state == "recall" and robot_state not in (ROBOT_HOME, ROBOT_ARRIVED):
                    send_to_robot(ser, "H", quiet=True)

            # --- 방향 B: 펫 state 파일 변화 감지 ---
            if now >= next_pet_poll:
                next_pet_poll = now + PET_STATE_POLL_SEC
                cur = read_state(bridge_dir)
                if cur is not None and cur != last_state:
                    print(f"[펫 state] {last_state or '(없음)'} → {cur}")
                    if cur == "home":
                        # 펫이 볼에 들어감 = 로봇 차례 → 주행(도착·귀가 중이어도
                        # 이건 새로운 의도이므로 F 전송). recall 취소로 돌아온
                        # 경우도 여기 → 로봇은 다시 자유 주행.
                        send_to_robot(ser, "F", "펫이 집에 들어감 → 로봇 자유 주행")
                    elif cur == "recall":
                        # 사용자가 볼을 눌러 펫을 다시 부름 = 로봇은 도킹으로 귀가.
                        # 로봇이 ARRIVED 하면 방향 A(폴링/ARRIVED)가 exit_home 을
                        # 써서 펫을 꺼낸다. A-5(아래)가 'H' 유실도 보정한다.
                        send_to_robot(ser, "H", "펫 소환 → 로봇 귀가(도킹)")
                    elif cur == "virtual":
                        # A-4: 펫이 볼에서 나옴 = 로봇은 쉴 차례 → 정지.
                        send_to_robot(ser, "S", "펫이 볼에서 나옴 → 로봇 정지")
                    last_state = cur

            # --- 수동 트리거: 키보드 ---
            if poll_keyboard(ser):
                print("[종료] 키 입력으로 브리지 정지")
                break

            time.sleep(0.01)
    finally:
        # A-4: 어떤 경로로 종료하든(q/Esc/Ctrl+C) 로봇을 세우고 나간다.
        if ser is not None:
            send_to_robot(ser, "S", "브리지 종료 → 로봇 정지")
            try:
                ser.close()
            except Exception:
                pass


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[종료] 브리지 정지")
